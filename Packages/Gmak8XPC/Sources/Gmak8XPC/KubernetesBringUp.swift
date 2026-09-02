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
    private let apiPort: @Sendable () -> Int
    private let checkAPI: @Sendable (Int) async -> Bool
    private let pollInterval: Duration
    private let stepTimeout: Duration
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(
        makeClient: @escaping @Sendable () async throws -> GuestAgentClient,
        kubeconfigStore: KubeconfigStore,
        setCurrentContext: Bool,
        matrix: CompatibilityMatrix = .bundled,
        apiPort: @escaping @Sendable () -> Int,
        checkAPI: (@Sendable (Int) async -> Bool)? = nil,
        pollInterval: Duration = .milliseconds(200),
        stepTimeout: Duration = .seconds(120)
    ) {
        self.makeClient = makeClient
        self.kubeconfigStore = kubeconfigStore
        self.setCurrentContext = setCurrentContext
        self.matrix = matrix
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
        log: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        let work = Task {
            do {
                let result = try await self.run(
                    generation: generation, isCurrent: isCurrent, setStep: setStep, log: log)
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

    private func run(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
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

        setStep(ClusterStartStep.airgap)

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

        return ClusterBringUpResult(apiEndpoint: "https://127.0.0.1:\(port)")
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
}

private final class DataBox: @unchecked Sendable {
    var value = Data()
}
