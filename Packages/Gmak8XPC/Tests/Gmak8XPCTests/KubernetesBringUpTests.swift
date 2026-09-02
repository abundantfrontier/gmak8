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
        let env = try BringUpHarness(yaml: k3sYAML, dataDirMinor: "1.32")
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().state == .failed
        }
        let message = env.engine.currentStatus().lastError ?? ""
        #expect(message.contains("1.32"))
        #expect(message.lowercased().contains("reset"))
        #expect(env.engine.currentStatus().apiEndpoint == nil)
    }

    @Test func cancelDuringBringUpHonorsStop() async throws {
        let env = try BringUpHarness(yaml: k3sYAML, neverReady: true)
        defer { env.tearDown() }

        #expect(env.engine.submit(.start) == .ok)
        env.scheduler.runNext()
        try await waitUntil {
            env.engine.currentStatus().step == ClusterStartStep.guestAgent
                || env.engine.currentStatus().step == ClusterStartStep.dataDisk
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
}

private struct BringUpHarness {
    var root: URL
    var store: KubeconfigStore
    var scheduler: ManualEngineScheduler
    var engine: ClusterEngine
    var server: BringUpHTTPServer
    var steps: [String] { tracker.steps }

    private let tracker: StepTracker

    init(
        yaml: String,
        apiPort: Int = 6443,
        dataDirMinor: String = "1.33",
        neverReady: Bool = false
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
            environment: ["KUBECONFIG": "/tmp/gmak8-do-not-merge"]
        )
        let state = BringUpAgentState(
            yaml: Data(yaml.utf8),
            dataDirMinor: dataDirMinor,
            neverReady: neverReady
        )
        server = try BringUpHTTPServer(state: state)
        tracker = StepTracker()
        let recorded = tracker
        let agentURL = server.url
        let bringUp = KubernetesBringUp(
            makeClient: {
                GuestAgentClient(baseURL: agentURL)
            },
            kubeconfigStore: store,
            setCurrentContext: false,
            apiPort: { apiPort },
            checkAPI: { _ in true },
            pollInterval: .milliseconds(5),
            stepTimeout: .seconds(2)
        )
        let wrapped = RecordingBringUp(inner: bringUp, tracker: recorded)
        scheduler = ManualEngineScheduler()
        engine = ClusterEngine(scheduler: scheduler, bringUp: wrapped)
    }

    func tearDown() {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class StepTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var steps: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func add(_ step: String) {
        lock.lock()
        storage.append(step)
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
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        inner.start(
            generation: generation,
            isCurrent: isCurrent,
            setStep: { step in
                tracker.add(step)
                setStep(step)
            },
            completion: completion
        )
    }

    func cancel() {
        inner.cancel()
    }
}

private final class BringUpAgentState: @unchecked Sendable {
    var yaml: Data
    var dataDirMinor: String
    var neverReady: Bool

    init(yaml: Data, dataDirMinor: String, neverReady: Bool) {
        self.yaml = yaml
        self.dataDirMinor = dataDirMinor
        self.neverReady = neverReady
    }
}

private final class BringUpHTTPServer: @unchecked Sendable {
    private let listenFD: Int32
    let port: UInt16
    private let queue = DispatchQueue(label: "gmak8.xpc.test.http")
    private var source: DispatchSourceRead?
    private let state: BringUpAgentState

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
            let (status, body, contentType) = response(for: request, state: state)
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

private func response(for request: (String, String), state: BringUpAgentState) -> (Int, Data, String) {
    switch (request.0, request.1) {
    case ("GET", "/health"):
        return (200, Data(#"{"ok":true}"#.utf8), "application/json")
    case ("GET", "/disks"):
        return (
            200,
            Data(
                #"{"gmak8_data":"mounted","kite_data":"mounted","mountpoint":"/mnt/data","label":"GMAK8_DATA","bytes_total":100,"bytes_free":40}"#
                    .utf8),
            "application/json"
        )
    case ("GET", "/k3s"):
        if state.neverReady {
            return (
                200,
                Data(#"{"active":false,"version":"v1.33.3+k3s1","data_dir_minor":"1.33","data_dir_exists":true}"#.utf8),
                "application/json"
            )
        }
        let json =
            "{\"active\":true,\"version\":\"v1.33.3+k3s1\",\"data_dir_minor\":\"\(state.dataDirMinor)\",\"data_dir_exists\":true}"
        return (200, Data(json.utf8), "application/json")
    case ("GET", "/kubeconfig"):
        return (200, state.yaml, "application/yaml")
    case ("GET", "/node"):
        if state.neverReady {
            return (200, Data(#"{"ready":false,"name":"gmak8"}"#.utf8), "application/json")
        }
        return (200, Data(#"{"ready":true,"name":"gmak8"}"#.utf8), "application/json")
    default:
        return (404, Data(#"{"ok":false,"error":"not found"}"#.utf8), "application/json")
    }
}

private func readHTTPRequest(fd: Int32) -> (String, String)? {
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
    guard let headerText = String(data: buffer, encoding: .utf8) else {
        return nil
    }
    let requestLine = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).first
    let parts = requestLine?.split(separator: " ") ?? []
    guard parts.count >= 2 else {
        return nil
    }
    return (String(parts[0]), String(parts[1]))
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
