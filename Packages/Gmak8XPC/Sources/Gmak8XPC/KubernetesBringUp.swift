import Foundation
import Gmak8GuestClient
import Gmak8Kit

/// Polls the guest agent after VM power-on. Must not run on `dev.gmak8.vm`.
public final class KubernetesBringUp: ClusterBringUp, @unchecked Sendable {
    public var isNoOp: Bool { false }

    private let makeClient: @Sendable () async throws -> GuestAgentClient
    private let kubeconfigStore: KubeconfigStore
    private let setCurrentContext: Bool
    private let matrix: CompatibilityMatrix
    private let airgapProvider: any AirgapProviding
    private let kubevirtAirgapProvider: (any AirgapProviding)?
    private let installKubeVirt: Bool
    private let startSSHD: @Sendable () -> Bool
    private let apiPort: @Sendable () -> Int
    private let checkAPI: @Sendable (Int) async -> Bool
    private let pollInterval: Duration
    private let stepTimeout: Duration
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var workInFlight = false

    public init(
        makeClient: @escaping @Sendable () async throws -> GuestAgentClient,
        kubeconfigStore: KubeconfigStore,
        setCurrentContext: Bool,
        matrix: CompatibilityMatrix = .bundled,
        airgapProvider: (any AirgapProviding)? = nil,
        kubevirtAirgapProvider: (any AirgapProviding)? = nil,
        installKubeVirt: Bool = false,
        startSSHD: @escaping @Sendable () -> Bool = { false },
        apiPort: @escaping @Sendable () -> Int,
        checkAPI: (@Sendable (Int) async -> Bool)? = nil,
        pollInterval: Duration = .milliseconds(200),
        stepTimeout: Duration = .seconds(180)
    ) {
        self.makeClient = makeClient
        self.kubeconfigStore = kubeconfigStore
        self.setCurrentContext = setCurrentContext
        self.matrix = matrix
        self.airgapProvider = airgapProvider ?? HostAirgapProvider(paths: .current())
        self.kubevirtAirgapProvider = kubevirtAirgapProvider
        self.installKubeVirt = installKubeVirt
        self.startSSHD = startSSHD
        self.apiPort = apiPort
        self.checkAPI =
            checkAPI ?? { port in
                await APIReadyz.isReady(port: port)
            }
        self.pollInterval = pollInterval
        self.stepTimeout = stepTimeout
    }

    public func start(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        setImageJob: @escaping @Sendable (ImageJobStatus?) -> Void,
        log: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        let work = Task {
            self.markWorkInFlight(true)
            defer { self.markWorkInFlight(false) }
            do {
                let result = try await self.run(
                    generation: generation,
                    isCurrent: isCurrent,
                    setStep: setStep,
                    setImageJob: setImageJob,
                    log: log)
                if Task.isCancelled || !isCurrent(generation) {
                    return
                }
                completion(.success(result))
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled || !isCurrent(generation) {
                    return
                }
                completion(.failure(error))
            }
        }
        lock.lock()
        task = work
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        task?.cancel()
        lock.unlock()
    }

    func isWorkInFlight() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return workInFlight
    }

    private func markWorkInFlight(_ value: Bool) {
        lock.lock()
        workInFlight = value
        lock.unlock()
    }

    private func run(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        setImageJob: @escaping @Sendable (ImageJobStatus?) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> ClusterBringUpResult {
        try await wait(
            generation: generation, isCurrent: isCurrent, setStep: setStep, step: ClusterStartStep.guestAgent
        ) {
            let client = try await self.makeClient()
            return try await client.health().ok
        }

        try await wait(generation: generation, isCurrent: isCurrent, setStep: setStep, step: ClusterStartStep.dataDisk)
        {
            let client = try await self.makeClient()
            return try await client.disks().isDataMounted
        }

        do {
            _ = try await makeClient().applyHostMounts()
        } catch let error as GuestAgentError {
            if case .httpStatus(let code, _) = error, code == 404 {
                log("host mounts: guest image has no /host-mounts")
            } else {
                log("host mounts: \(error.localizedDescription)")
            }
        } catch {
            log("host mounts: \(error.localizedDescription)")
        }

        try Task.checkCancellation()
        guard isCurrent(generation) else {
            throw CancellationError()
        }
        let probeClient = try await makeClient()
        let k3sProbe = try await probeClient.k3s()
        if !matrix.accepts(dataDirMinor: k3sProbe.dataDirMinor, dataDirExists: k3sProbe.dataDirExists) {
            throw ClusterBringUpError(
                message: matrix.refusalMessage(dataDirMinor: k3sProbe.dataDirMinor ?? "")
            )
        }

        try await importAirgapIfNeeded(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            setImageJob: setImageJob
        )

        try await wait(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            step: ClusterStartStep.kubernetes
        ) {
            let client = try await self.makeClient()
            if try await client.k3s().active {
                return true
            }
            try await client.startK3s()
            return try await client.k3s().active
        }

        let yamlBox = DataBox()
        try await wait(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            step: ClusterStartStep.kubernetes
        ) {
            let client = try await self.makeClient()
            yamlBox.value = try await client.kubeconfig()
            return !yamlBox.value.isEmpty
        }

        let port = apiPort()
        let text = String(data: yamlBox.value, encoding: .utf8) ?? ""
        let material = try K3sKubeconfig.localhostMaterial(from: text, port: port)
        do {
            _ = try kubeconfigStore.apply(material: material, setCurrentContext: setCurrentContext)
        } catch let error as KubeconfigError {
            switch error {
            case .userConfigNotYAML(_, let snippet), .unspliceableUserConfig(_, let snippet):
                log("user kubeconfig left untouched; \(snippet)")
            case .lockFailed:
                log("user kubeconfig lock failed; \(kubeconfigStore.exportSnippet)")
            }
        }

        try await wait(generation: generation, isCurrent: isCurrent, setStep: setStep, step: ClusterStartStep.api) {
            await self.checkAPI(port)
        }

        try await wait(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            step: ClusterStartStep.nodeReady
        ) {
            let client = try await self.makeClient()
            return try await client.node().ready
        }

        if startSSHD() {
            try await startSSHDIfNeeded(
                generation: generation, isCurrent: isCurrent, setStep: setStep, log: log)
        }

        if installKubeVirt {
            try await installKubeVirtIfNeeded(
                generation: generation,
                isCurrent: isCurrent,
                setStep: setStep,
                setImageJob: setImageJob,
                log: log
            )
        }

        let kvmPresent = await probeKvm(log: log)
        return ClusterBringUpResult(apiEndpoint: "https://127.0.0.1:\(port)", kvmPresent: kvmPresent)
    }

    private func startSSHDIfNeeded(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        setStep(ClusterStartStep.sshd)
        try Task.checkCancellation()
        guard isCurrent(generation) else {
            throw CancellationError()
        }
        do {
            let report = try await makeClient().startSSHD()
            log(report.running ? "guest sshd running" : "guest sshd start returned not running")
        } catch let error as GuestAgentError {
            if case .httpStatus(let code, _) = error, code == 404 {
                log("sshd: guest image has no /sshd/start")
                return
            }
            throw ClusterBringUpError(message: error.localizedDescription)
        }
    }

    private func installKubeVirtIfNeeded(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        setImageJob: @escaping @Sendable (ImageJobStatus?) -> Void,
        log: @escaping @Sendable (String) -> Void
    ) async throws {
        setStep(ClusterStartStep.kubeVirt)
        try Task.checkCancellation()
        guard isCurrent(generation) else {
            throw CancellationError()
        }
        if let provider = kubevirtAirgapProvider, let archive = try? provider.resolvedArchive() {
            do {
                let client = try await makeClient()
                setImageJob(ImageJobStatus(bytesReceived: 0, bytesTotal: archive.byteCount))
                _ = try await client.importKubevirtAirgap(
                    fileURL: archive.url, name: archive.fileName
                ) { received, total in
                    setImageJob(ImageJobStatus(bytesReceived: received, bytesTotal: total))
                }
                setImageJob(nil)
            } catch let error as GuestAgentError {
                if case .httpStatus(let code, _) = error, code == 404 {
                    log("kubevirt airgap: guest image has no /airgap/kubevirt")
                } else {
                    log("kubevirt airgap: \(error.localizedDescription)")
                }
                setImageJob(nil)
            }
        }
        do {
            let report = try await makeClient().installKubeVirt()
            log("kubevirt phase \(report.phase) u1.nano=\(report.u1Nano)")
        } catch let error as GuestAgentError {
            if case .httpStatus(let code, _) = error, code == 404 {
                log("kubevirt: guest image has no /kubevirt/install")
                return
            }
            throw ClusterBringUpError(message: error.localizedDescription)
        }
        try await wait(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            step: ClusterStartStep.kubeVirt
        ) {
            let report = try await self.makeClient().kubevirt()
            return report.u1Nano || report.phase == "Deployed"
        }
    }

    private func probeKvm(log: @escaping @Sendable (String) -> Void) async -> Bool {
        do {
            let present = try await makeClient().kvm().kvm
            log(present ? "guest /dev/kvm present" : "guest /dev/kvm absent")
            return present
        } catch {
            log("kvm: \(error.localizedDescription)")
            return false
        }
    }

    private func wait(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        step: String,
        predicate: @escaping @Sendable () async throws -> Bool
    ) async throws {
        setStep(step)
        let deadline = ContinuousClock.now + stepTimeout
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard isCurrent(generation) else {
                throw CancellationError()
            }
            do {
                if try await predicate() {
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Agent not up yet; keep polling.
            }
            try await Task.sleep(for: pollInterval)
        }
        throw ClusterBringUpError(message: "Timed out waiting for \(step)")
    }

    private func importAirgapIfNeeded(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        setImageJob: @escaping @Sendable (ImageJobStatus?) -> Void
    ) async throws {
        setStep(ClusterStartStep.airgap)
        try Task.checkCancellation()
        guard isCurrent(generation) else {
            throw CancellationError()
        }
        let client = try await makeClient()
        if try await client.airgap().present {
            setImageJob(nil)
            return
        }
        let archive: AirgapLocalArchive
        do {
            archive = try airgapProvider.resolvedArchive()
        } catch let error as AirgapError {
            throw ClusterBringUpError(message: error.localizedDescription)
        } catch let error as ClusterBringUpError {
            throw error
        } catch {
            throw ClusterBringUpError(message: error.localizedDescription)
        }
        let disks = try await client.disks()
        if !AirgapVerifier.fitsOnDataDisk(archiveBytes: archive.byteCount, bytesFree: disks.bytesFree) {
            throw ClusterBringUpError(
                message: AirgapError.insufficientDisk(
                    needed: AirgapVerifier.requiredFreeBytes(archiveBytes: archive.byteCount),
                    free: disks.bytesFree
                ).localizedDescription
            )
        }
        setImageJob(ImageJobStatus(bytesReceived: 0, bytesTotal: archive.byteCount))
        do {
            _ = try await client.importAirgap(fileURL: archive.url, name: archive.fileName) { received, total in
                setImageJob(ImageJobStatus(bytesReceived: received, bytesTotal: total))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GuestAgentError {
            try Task.checkCancellation()
            throw ClusterBringUpError(message: error.localizedDescription)
        }
        try await wait(
            generation: generation,
            isCurrent: isCurrent,
            setStep: setStep,
            step: ClusterStartStep.airgap
        ) {
            try await client.airgap().present
        }
        setImageJob(nil)
    }
}

private final class DataBox: @unchecked Sendable {
    var value = Data()
}
