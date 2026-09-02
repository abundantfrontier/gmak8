import Darwin
import Foundation
import Gmak8GuestClient
import Gmak8Kit
import Testing

@testable import Gmak8XPC

struct KubernetesBringUpTests {
    private let k3sYAML = """
        apiVersion: v1
        kind: Config
        clusters:
        - cluster:
            certificate-authority-data: CA_DATA
            server: https://192.168.127.2:6443
          name: default
        users:
        - name: default
          user:
            client-certificate-data: CERT_DATA
            client-key-data: KEY_DATA
        """

    @Test func hostAirgapProviderFailsWhenCacheMissing() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-airgap-provider-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = HostPaths(
            applicationSupport: root.appending(path: "Application Support/dev.gmak8.app"),
            caches: root.appending(path: "Caches/dev.gmak8.app"),
            logs: root.appending(path: "Logs/gmak8")
        )
        let provider = HostAirgapProvider(paths: paths, publicKeyPEM: "not-a-key")
        do {
            _ = try provider.resolvedArchive()
            Issue.record("expected missing archive")
        } catch let error as AirgapError {
            #expect(error.localizedDescription.contains("docker.io/rancher"))
        }
    }

    @Test func fakePathStillRunsWithoutAgent() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().step == "fakeVM")
        #expect(engine.currentStatus().apiEndpoint == nil)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.currentStatus().step == "fakeVM")
        #expect(engine.currentStatus().apiEndpoint == nil)
        #expect(engine.currentStatus().publishedPorts.isEmpty)
    }

    @Test func bootstrapReachesRunningAndWritesKubeconfig() async throws {
        let env = try BringUpHarness(yaml: k3sYAML)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        #expect(env.engine.currentStatus().apiEndpoint == "https://127.0.0.1:6443")
        #expect(env.engine.currentStatus().step == ClusterStartStep.nodeReady)
        let privateYAML = try String(contentsOf: env.store.privateKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("server: https://127.0.0.1:6443"))
        #expect(env.steps.contains(ClusterStartStep.guestAgent))
        #expect(env.steps.contains(ClusterStartStep.dataDisk))
        #expect(env.steps.contains(ClusterStartStep.airgap))
        #expect(env.steps.contains(ClusterStartStep.kubernetes))
        #expect(env.steps.contains(ClusterStartStep.api))
        #expect(env.steps.contains(ClusterStartStep.nodeReady))
        #expect(env.server.state.airgapImports == 0)
        #expect(env.server.state.k3sStarts == 1)
    }

    @Test func presentAirgapSkipsImport() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, airgapPresent: true)
        defer { env.tearDown() }
        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        #expect(env.server.state.airgapImports == 0)
        #expect(env.server.state.k3sStarts == 1)
        #expect(env.steps.contains(ClusterStartStep.airgap))
    }

    @Test func healthOkDoesNotSkipUnmountedDataDisk() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, mounted: false)
        defer { env.tearDown() }
        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().step == ClusterStartStep.dataDisk
        }
        #expect(env.engine.currentStatus().state == .starting)
        #expect(env.server.state.k3sStarts == 0)
        env.server.state.mounted = true
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        #expect(env.engine.currentStatus().apiEndpoint == "https://127.0.0.1:6443")
        #expect(env.steps.contains(ClusterStartStep.dataDisk))
        #expect(env.steps.contains(ClusterStartStep.guestAgent))
    }

    @Test func bootstrapRewritesApiPort16443() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, apiPort: 16_443)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        #expect(env.engine.currentStatus().apiEndpoint == "https://127.0.0.1:16443")
        let privateYAML = try String(contentsOf: env.store.privateKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("server: https://127.0.0.1:16443"))
    }

    @Test func compatibilityRefuse132() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, dataDirMinor: "1.32", dataDirExists: true)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopping
        }
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        let message = env.engine.currentStatus().lastError ?? ""
        #expect(message.contains("1.32"))
        #expect(message.lowercased().contains("reset"))
        #expect(env.engine.currentStatus().apiEndpoint == nil)
    }

    @Test func compatibilityRefuseUnknownExistingDataDir() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, dataDirMinor: "", dataDirExists: true)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopping
        }
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        let message = env.engine.currentStatus().lastError ?? ""
        #expect(message.contains("unknown"))
        #expect(message.lowercased().contains("reset"))
    }

    @Test func unspliceableUserKubeconfigDoesNotFailBringUp() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, mergeUserConfig: true)
        defer { env.tearDown() }
        try FileManager.default.createDirectory(
            at: env.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "this is not: [yaml\n".write(to: env.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        let privateYAML = try String(contentsOf: env.store.privateKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("server: https://127.0.0.1:6443"))
        #expect(try String(contentsOf: env.store.userKubeconfigFile, encoding: .utf8).contains("this is not"))
        #expect(env.logs.contains { $0.contains("export KUBECONFIG=") })
    }

    @Test func bringUpFailureStopConflictsWithConcurrentStart() async throws {
        let runtime = SlowStopRuntime()
        let env = try BringUpHarness(
            yaml: k3sYAML, dataDirMinor: "1.32", dataDirExists: true, runtime: runtime)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopping
        }
        #expect(env.engine.submit(.start) == .error(.conflict))
        DispatchQueue.global(qos: .userInitiated).async {
            env.scheduler.runNext()
        }
        runtime.waitUntilStopEntered()
        #expect(env.engine.submit(.start) == .error(.conflict))
        runtime.finishStop()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        #expect(env.engine.currentStatus().lastError?.contains("1.32") == true)
        #expect(env.engine.submit(.start) == .ok)
    }

    @Test func cancelDuringBringUpHonorsStop() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, neverReady: true)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().step == ClusterStartStep.guestAgent
                || env.engine.currentStatus().step == ClusterStartStep.dataDisk
                || env.engine.currentStatus().step == ClusterStartStep.airgap
                || env.engine.currentStatus().step == ClusterStartStep.kubernetes
        }
        #expect(env.engine.submit(.stop) == .ok)
        #expect(env.engine.currentStatus().state == .stopping)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopped
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(env.engine.currentStatus().state == .stopped)
        #expect(env.engine.currentStatus().apiEndpoint == nil)
    }

    @Test func missingAirgapFailsWithoutStartingK3s() async throws {
        let env = try BringUpHarness(
            yaml: k3sYAML, airgapPresent: false, airgapProvider: MissingAirgapProvider())
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopping
        }
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        let message = env.engine.currentStatus().lastError ?? ""
        #expect(message.contains("docker.io/rancher"))
        #expect(env.server.state.k3sStarts == 0)
        #expect(env.server.state.events.filter { $0 == "k3s" }.isEmpty)
    }

    @Test func airgapImportRunsBeforeK3sStart() async throws {
        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-bringup-airgap-\(UUID().uuidString).tar")
        try Data("tiny-airgap-fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let env = try BringUpHarness(
            yaml: k3sYAML,
            airgapPresent: false,
            airgapProvider: FileAirgapProvider(url: fixture)
        )
        defer { env.tearDown() }

        let sawJob = FlagBox()
        _ = env.engine.subscribe { event in
            if case .status(let status) = event, status.imageJob != nil {
                sawJob.set()
            }
        }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .running
        }
        #expect(env.server.state.events.contains("airgap"))
        #expect(env.server.state.events.contains("k3s"))
        let airgapIndex = env.server.state.events.firstIndex(of: "airgap") ?? .max
        let k3sIndex = env.server.state.events.firstIndex(of: "k3s") ?? .min
        #expect(airgapIndex < k3sIndex)
        #expect(env.server.state.lastAirgapBody == Data("tiny-airgap-fixture".utf8))
        #expect(sawJob.value)
        #expect(env.engine.currentStatus().imageJob == nil)
        #expect(env.steps.contains(ClusterStartStep.airgap))
    }

    @Test func airgapPreflightRefusesTightDisk() async throws {
        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-bringup-airgap-\(UUID().uuidString).tar")
        try Data(repeating: 0x61, count: 100).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let env = try BringUpHarness(
            yaml: k3sYAML,
            bytesFree: 1,
            airgapPresent: false,
            airgapProvider: FileAirgapProvider(url: fixture)
        )
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopping
        }
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        let message = env.engine.currentStatus().lastError ?? ""
        #expect(message.contains("20%"))
        #expect(env.server.state.k3sStarts == 0)
        #expect(env.server.state.airgapImports == 0)
    }

    @Test func cancelDuringAirgapPutDoesNotStartK3s() async throws {
        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-bringup-airgap-\(UUID().uuidString).tar")
        try Data("tiny-airgap-fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let env = try BringUpHarness(
            yaml: k3sYAML,
            airgapPresent: false,
            holdAirgapPut: true,
            streamClient: true,
            airgapProvider: FileAirgapProvider(url: fixture)
        )
        defer {
            env.server.state.releaseAirgapPut()
            env.tearDown()
        }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        #expect(env.server.state.waitUntilAirgapPutStarted())
        #expect(env.engine.submit(.stop) == .ok)
        #expect(env.engine.currentStatus().state == .stopping)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .stopped
        }
        try await waitUntil(timeout: .seconds(1)) {
            !env.kubernetesBringUp.isWorkInFlight()
        }
        env.server.state.releaseAirgapPut()
        try await Task.sleep(for: .milliseconds(50))
        #expect(env.engine.currentStatus().state == .stopped)
        #expect(env.engine.currentStatus().apiEndpoint == nil)
        #expect(env.server.state.k3sStarts == 0)
        #expect(!env.sawBringUpSuccess)
    }
}

private struct BringUpHarness {
    var root: URL
    var store: KubeconfigStore
    var scheduler: ManualEngineScheduler
    var engine: ClusterEngine
    var server: BringUpHTTPServer
    var kubernetesBringUp: KubernetesBringUp
    var steps: [String] { tracker.steps }
    var logs: [String] { tracker.logs }
    var sawBringUpSuccess: Bool { tracker.sawSuccess }

    private let tracker: StepTracker

    init(
        yaml: String,
        apiPort: Int = 6443,
        dataDirMinor: String = "",
        dataDirExists: Bool = false,
        neverReady: Bool = false,
        mergeUserConfig: Bool = false,
        bytesFree: UInt64 = 1_000_000,
        mounted: Bool = true,
        airgapPresent: Bool = true,
        holdAirgapPut: Bool = false,
        streamClient: Bool = false,
        airgapProvider: (any AirgapProviding)? = nil,
        runtime: (any VirtualMachineRuntime)? = nil
    ) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-bringup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = KubeconfigStore(
            hostPaths: HostPaths(
                applicationSupport: root.appending(path: "Application Support/dev.gmak8.app"),
                caches: root.appending(path: "Caches/dev.gmak8.app"),
                logs: root.appending(path: "Logs/gmak8")
            ),
            userKubeconfigFile: root.appending(path: ".kube/config"),
            environment: mergeUserConfig ? [:] : ["KUBECONFIG": "/tmp/gmak8-do-not-merge"]
        )
        let state = BringUpAgentState(
            yaml: Data(yaml.utf8),
            dataDirMinor: dataDirMinor,
            dataDirExists: dataDirExists,
            neverReady: neverReady,
            bytesFree: bytesFree,
            mounted: mounted,
            airgapPresent: airgapPresent,
            holdAirgapPut: holdAirgapPut
        )
        server = try BringUpHTTPServer(state: state)
        tracker = StepTracker()
        let recorded = tracker
        let port = server.port
        let agentURL = server.url
        let makeClient: @Sendable () async throws -> GuestAgentClient
        if streamClient {
            makeClient = {
                GuestAgentClient {
                    try TCPGuestChannel.connect(host: "127.0.0.1", port: port)
                }
            }
        } else {
            makeClient = {
                GuestAgentClient(baseURL: agentURL)
            }
        }
        let bringUp = KubernetesBringUp(
            makeClient: makeClient,
            kubeconfigStore: store,
            setCurrentContext: false,
            airgapProvider: airgapProvider,
            apiPort: { apiPort },
            checkAPI: { _ in true },
            pollInterval: .milliseconds(5),
            stepTimeout: .seconds(2)
        )
        kubernetesBringUp = bringUp
        let wrapped = RecordingBringUp(inner: bringUp, tracker: recorded)
        scheduler = ManualEngineScheduler()
        engine = ClusterEngine(
            scheduler: scheduler, runtime: runtime ?? FakeVirtualMachineRuntime(), bringUp: wrapped)
    }

    func tearDown() {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class StepTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var logStorage: [String] = []
    var steps: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    var logs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return logStorage
    }
    func add(_ step: String) {
        lock.lock()
        storage.append(step)
        lock.unlock()
    }
    func addLog(_ line: String) {
        lock.lock()
        logStorage.append(line)
        lock.unlock()
    }
    private var success = false
    var sawSuccess: Bool {
        lock.lock()
        defer { lock.unlock() }
        return success
    }
    func noteCompletion(_ result: Result<ClusterBringUpResult, any Error>) {
        lock.lock()
        if case .success = result {
            success = true
        }
        lock.unlock()
    }
}

private struct RecordingBringUp: ClusterBringUp {
    var isNoOp: Bool { false }
    let inner: KubernetesBringUp
    let tracker: StepTracker

    func start(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        setImageJob: @escaping @Sendable (ImageJobStatus?) -> Void,
        log: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        inner.start(
            generation: generation,
            isCurrent: isCurrent,
            setStep: { step in
                tracker.add(step)
                setStep(step)
            },
            setImageJob: setImageJob,
            log: { line in
                tracker.addLog(line)
                log(line)
            },
            completion: { result in
                tracker.noteCompletion(result)
                completion(result)
            }
        )
    }

    func cancel() {
        inner.cancel()
    }
}

private final class BringUpAgentState: @unchecked Sendable {
    var yaml: Data
    var dataDirMinor: String
    var dataDirExists: Bool
    var neverReady: Bool
    var bytesFree: UInt64
    var mounted: Bool
    var airgapPresent: Bool
    var started = false
    var k3sStarts = 0
    var airgapImports = 0
    var lastAirgapBody = Data()
    var events: [String] = []
    var holdAirgapPut: Bool
    private let putLock = NSCondition()
    private var airgapPutStarted = false

    init(
        yaml: Data,
        dataDirMinor: String,
        dataDirExists: Bool,
        neverReady: Bool,
        bytesFree: UInt64,
        mounted: Bool,
        airgapPresent: Bool,
        holdAirgapPut: Bool = false
    ) {
        self.yaml = yaml
        self.dataDirMinor = dataDirMinor
        self.dataDirExists = dataDirExists
        self.neverReady = neverReady
        self.bytesFree = bytesFree
        self.mounted = mounted
        self.airgapPresent = airgapPresent
        self.holdAirgapPut = holdAirgapPut
    }

    func noteAirgapPutStartedAndWaitIfHeld() {
        putLock.lock()
        airgapPutStarted = true
        putLock.broadcast()
        let deadline = Date().addingTimeInterval(5)
        while holdAirgapPut && Date() < deadline {
            _ = putLock.wait(until: Date().addingTimeInterval(0.05))
        }
        putLock.unlock()
    }

    func waitUntilAirgapPutStarted(timeout: TimeInterval = 5) -> Bool {
        putLock.lock()
        defer { putLock.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while !airgapPutStarted {
            if !putLock.wait(until: deadline) {
                return false
            }
        }
        return true
    }

    func releaseAirgapPut() {
        putLock.lock()
        holdAirgapPut = false
        putLock.broadcast()
        putLock.unlock()
    }
}

private final class BringUpHTTPServer: @unchecked Sendable {
    private let listenFD: Int32
    let port: UInt16
    private let queue = DispatchQueue(label: "gmak8.xpc.test.http")
    private var source: DispatchSourceRead?
    let state: BringUpAgentState

    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    init(state: BringUpAgentState) throws {
        self.state = state
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        if listen(fd, 16) != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        if nameResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        listenFD = fd
        port = UInt16(bigEndian: bound.sin_port)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        Darwin.close(listenFD)
    }

    private func acceptOnce() {
        let client = accept(listenFD, nil, nil)
        if client < 0 {
            return
        }
        queue.async { [state] in
            defer { Darwin.close(client) }
            guard let request = readHTTPRequest(fd: client) else {
                return
            }
            let (status, body, contentType) = response(
                for: (request.method, request.path, request.body), state: state)
            let header =
                "HTTP/1.1 \(status) OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(header.utf8)
            payload.append(body)
            payload.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                var offset = 0
                while offset < rawBuffer.count {
                    let written = Darwin.write(client, base + offset, rawBuffer.count - offset)
                    if written <= 0 {
                        return
                    }
                    offset += written
                }
            }
        }
    }
}

private func response(for request: (String, String, Data), state: BringUpAgentState) -> (Int, Data, String) {
    switch (request.0, request.1) {
    case ("GET", "/health"):
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    case ("GET", "/disks"):
        if !state.mounted {
            return (
                200,
                Data(
                    #"{"gmak8_data":"unmounted","kite_data":"unmounted","mountpoint":"/mnt/data","label":"","bytes_total":0,"bytes_free":0}"#
                        .utf8),
                "application/json"
            )
        }
        let json =
            "{\"gmak8_data\":\"mounted\",\"kite_data\":\"mounted\",\"mountpoint\":\"/mnt/data\",\"label\":\"GMAK8_DATA\",\"bytes_total\":10000000,\"bytes_free\":\(state.bytesFree)}"
        return (200, Data(json.utf8), "application/json")
    case ("GET", "/k3s"):
        let active = state.started && !state.neverReady
        let minorJSON = state.dataDirMinor.isEmpty ? "null" : "\"\(state.dataDirMinor)\""
        let json =
            "{\"active\":\(active),\"version\":\"v1.33.3+k3s1\",\"data_dir_minor\":\(minorJSON),\"data_dir_exists\":\(state.dataDirExists)}"
        return (200, Data(json.utf8), "application/json")
    case ("POST", "/k3s/start"):
        state.started = true
        state.k3sStarts += 1
        state.events.append("k3s")
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    case ("GET", "/kubeconfig"):
        return (200, state.yaml, "application/yaml")
    case ("GET", "/node"):
        if state.neverReady {
            return (200, Data(#"{"ready":false,"name":"gmak8"}"#.utf8), "application/json")
        }
        return (200, Data(#"{"ready":true,"name":"gmak8"}"#.utf8), "application/json")
    case ("GET", "/airgap"):
        if state.airgapPresent {
            return (
                200,
                Data(#"{"present":true,"files":["gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"],"bytes":24}"#.utf8),
                "application/json"
            )
        }
        return (200, Data(#"{"present":false,"files":[],"bytes":0}"#.utf8), "application/json")
    case ("PUT", "/airgap/k3s"):
        state.noteAirgapPutStartedAndWaitIfHeld()
        state.airgapImports += 1
        state.lastAirgapBody = request.2
        state.airgapPresent = true
        state.events.append("airgap")
        let json =
            "{\"present\":true,\"files\":[\"gmak8-k3s-airgap-v1.33.3-arm64.tar.zst\"],\"bytes\":\(request.2.count)}"
        return (200, Data(json.utf8), "application/json")
    default:
        return (404, Data(#"{"ok":false,"error":"not found"}"#.utf8), "application/json")
    }
}

private struct BringUpHTTPRequest {
    var method: String
    var path: String
    var body: Data
}

private func readHTTPRequest(fd: Int32) -> BringUpHTTPRequest? {
    var buffer = Data()
    let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    var chunk = [UInt8](repeating: 0, count: 4096)
    while buffer.range(of: separator) == nil {
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count <= 0 {
            return nil
        }
        buffer.append(contentsOf: chunk.prefix(count))
        if buffer.count > 65_536 {
            return nil
        }
    }
    guard let range = buffer.range(of: separator) else {
        return nil
    }
    let headerText = String(data: buffer[buffer.startIndex..<range.lowerBound], encoding: .utf8) ?? ""
    let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let requestLine = lines.first else {
        return nil
    }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else {
        return nil
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else {
            continue
        }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        headers[name] = value
    }
    var body = Data(buffer[range.upperBound...])
    if let lengthText = headers["content-length"], let length = Int(lengthText) {
        while body.count < length {
            let count = Darwin.read(fd, &chunk, min(chunk.count, length - body.count))
            if count <= 0 {
                return nil
            }
            body.append(contentsOf: chunk.prefix(count))
        }
        body = Data(body.prefix(length))
    }
    return BringUpHTTPRequest(method: String(parts[0]), path: String(parts[1]), body: body)
}

private struct FileAirgapProvider: AirgapProviding {
    var url: URL

    func resolvedArchive() throws -> AirgapLocalArchive {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return AirgapLocalArchive(url: url, fileName: url.lastPathComponent, byteCount: size)
    }
}

private struct MissingAirgapProvider: AirgapProviding {
    func resolvedArchive() throws -> AirgapLocalArchive {
        throw AirgapError.missingArchive("/tmp/gmak8-missing-airgap.tar.zst")
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func set() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}

private final class SlowStopRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    private let lock = NSCondition()
    private var stopEntered = false
    private var allowStop = false

    func preflight() -> VirtualMachinePreflightError? {
        nil
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        lock.lock()
        stopEntered = true
        lock.broadcast()
        while !allowStop {
            lock.wait()
        }
        lock.unlock()
        completion(.success(()))
    }

    func waitUntilStopEntered() {
        lock.lock()
        let deadline = Date().addingTimeInterval(5)
        while !stopEntered {
            if !lock.wait(until: deadline) {
                break
            }
        }
        lock.unlock()
    }

    func finishStop() {
        lock.lock()
        allowStop = true
        lock.broadcast()
        lock.unlock()
    }
}

private func waitUntil(timeout: Duration = .seconds(5), _ predicate: @escaping () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for condition")
}
