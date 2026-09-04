import Darwin
import Foundation
import Gmak8XPC
import Testing

struct CLITests {
    @Test func statusTextIncludesStateAndAPIEndpoint() {
        let status = EngineStatus(state: .running, apiEndpoint: "https://127.0.0.1:6443")
        #expect(StatusText.render(status) == "State: Running\nAPI: https://127.0.0.1:6443")
    }

    @Test func statusTextOmitsAPIWhenMissing() {
        let status = EngineStatus(state: .stopped, apiEndpoint: nil)
        #expect(StatusText.render(status) == "State: Stopped")
    }

    @Test func statusTextListsPublishedLoopbackPorts() {
        let port = PublishedPort(
            service: "traefik",
            namespace: "kube-system",
            port: 80,
            nodePort: 31666,
            hostPort: 31666,
            guestPort: 31666,
            hostURL: "http://127.0.0.1:31666"
        )
        let status = EngineStatus(state: .running, apiEndpoint: "https://127.0.0.1:6443", publishedPorts: [port])
        #expect(
            StatusText.render(status)
                == "State: Running\nAPI: https://127.0.0.1:6443\nPort: http://127.0.0.1:31666 traefik"
        )
    }

    @Test func imageTextRendersUserAndSystemRows() {
        let list = NodeImageList(items: [
            NodeImage(id: "sha256:abc", refs: ["nginx:dev"], sizeBytes: 1024, system: false),
            NodeImage(
                id: "sha256:def",
                refs: ["docker.io/rancher/mirrored-pause:3.6"],
                sizeBytes: 26_214_400,
                system: true
            ),
        ])
        let text = ImageText.renderList(list)
        #expect(text.contains("nginx:dev"))
        #expect(text.contains("sha256:abc"))
        #expect(text.contains("1.0 KiB"))
        #expect(text.contains("system"))
        #expect(ImageText.renderList(NodeImageList()) == "No node images.")
        #expect(ImageText.formatBytes(512) == "512 B")
        #expect(ImageText.formatBytes(1024) == "1.0 KiB")
        #expect(ImageText.formatBytes(26_214_400) == "25.0 MiB")
    }

    @Test func imageLoadWaitFinishesOnJobClearAndImportedLog() {
        let wait = ImageLoadWait()
        wait.handle(
            .status(
                EngineStatus(
                    state: .running,
                    imageJob: ImageJobStatus(bytesReceived: 4, bytesTotal: 8)
                )
            )
        )
        wait.handle(.log(source: .engine, line: "imported sha256:abc nginx:dev"))
        wait.handle(.status(EngineStatus(state: .running, imageJob: nil)))
        #expect(wait.group.wait(timeout: .now() + 1) == .success)
        #expect(wait.importedLine == "imported sha256:abc nginx:dev")
        #expect(wait.status?.imageJob == nil)
        #expect(wait.error == nil)
    }

    @Test func imageLoadWaitFailsOnSubscribeError() {
        let wait = ImageLoadWait()
        wait.fail(.engineError(.conflict))
        #expect(wait.group.wait(timeout: .now() + 1) == .success)
        #expect(wait.error == .engineError(.conflict))
    }

    @Test func statusTextDisplayNamesMatchClusterStates() {
        #expect(StatusText.displayName(.stopped) == "Stopped")
        #expect(StatusText.displayName(.starting) == "Starting")
        #expect(StatusText.displayName(.running) == "Running")
        #expect(StatusText.displayName(.degraded) == "Degraded")
        #expect(StatusText.displayName(.paused) == "Paused")
        #expect(StatusText.displayName(.stopping) == "Stopping")
        #expect(StatusText.displayName(.failed) == "Failed")
    }

    @Test func codecRoundTripRendersRunningWithAPI() throws {
        let event = EngineEvent.status(
            EngineStatus(state: .running, apiEndpoint: "https://127.0.0.1:16443")
        )
        let line = try utf8Line(event)
        let decoded = try NDJSONCodec.decodeEvent(line: line)
        guard case .status(let status) = decoded else {
            Issue.record("expected status event")
            return
        }
        #expect(StatusText.render(status) == "State: Running\nAPI: https://127.0.0.1:16443")
    }

    @Test func missingSocketIsEngineNotRunning() {
        let url = URL(fileURLWithPath: "/tmp/gmak8-missing-\(UUID().uuidString).sock")
        #expect(throws: CLIError.engineNotRunning) {
            try EngineClient.status(socketURL: url)
        }
        #expect(CLIError.engineNotRunning.errorDescription == "gmak8-core is not running (engine.sock is missing).")
    }

    @Test func unauthorizedIsEngineErrorNotMissingSocket() throws {
        let socketURL = uniqueSocketURL()
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: ClusterEngine(scheduler: ManualEngineScheduler()),
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: "TEAMONLY")
        )
        try server.start()
        defer { server.stop() }

        #expect(throws: CLIError.engineError(.unauthorized)) {
            try EngineClient.status(socketURL: socketURL)
        }
        #expect(CLIError.engineError(.unauthorized).errorDescription == "gmak8-core returned error: unauthorized.")
    }

    @Test func hungListenerIsCommunicationFailedNotMissingSocket() throws {
        let path = uniqueSocketURL().path(percentEncoded: false)
        unlink(path)
        let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listenFD >= 0)
        defer {
            Darwin.close(listenFD)
            unlink(path)
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.withCString { cString in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: path.utf8.count + 1))
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listenFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bindResult == 0)
        try #require(listen(listenFD, 1) == 0)

        #expect(throws: CLIError.communicationFailed) {
            try EngineClient.status(
                socketURL: URL(fileURLWithPath: path),
                timeout: timeval(tv_sec: 0, tv_usec: 200_000)
            )
        }
        #expect(CLIError.communicationFailed.errorDescription == "could not talk to gmak8-core.")
    }

    @Test func statusOverFakeSocketUsesSameCodec() throws {
        let socketURL = uniqueSocketURL()
        let engine = ClusterEngine(scheduler: ManualEngineScheduler())
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
        defer { server.stop() }

        let status = try EngineClient.status(socketURL: socketURL)
        #expect(status.state == .stopped)
        #expect(StatusText.render(status) == "State: Stopped")
    }

    @Test func submitMissingSocketIsEngineNotRunning() {
        let url = URL(fileURLWithPath: "/tmp/gmak8-missing-\(UUID().uuidString).sock")
        #expect(throws: CLIError.engineNotRunning) {
            try EngineClient.submit(.start, socketURL: url)
        }
        #expect(throws: CLIError.engineNotRunning) {
            try EngineClient.subscribe(
                socketURL: url,
                onEvent: { _ in },
                onError: { _ in }
            )
        }
    }

    @Test func submitUnauthorizedIsEngineErrorNotMissingSocket() throws {
        let socketURL = uniqueSocketURL()
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: ClusterEngine(scheduler: ManualEngineScheduler()),
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: "TEAMONLY")
        )
        try server.start()
        defer { server.stop() }

        #expect(throws: CLIError.engineError(.unauthorized)) {
            try EngineClient.submit(.start, socketURL: socketURL)
        }
    }

    @Test func hungListenerSubmitIsCommunicationFailedNotMissingSocket() throws {
        let path = uniqueSocketURL().path(percentEncoded: false)
        unlink(path)
        let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listenFD >= 0)
        defer {
            Darwin.close(listenFD)
            unlink(path)
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.withCString { cString in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: path.utf8.count + 1))
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listenFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bindResult == 0)
        try #require(listen(listenFD, 1) == 0)

        #expect(throws: CLIError.communicationFailed) {
            try EngineClient.submit(
                .start,
                socketURL: URL(fileURLWithPath: path),
                timeout: timeval(tv_sec: 0, tv_usec: 200_000)
            )
        }
    }

    @Test func startAndStopSubmitSameOpsAsStatusClient() throws {
        let start = try NDJSONCodec.encodeLine(EngineRequest.start)
        let stop = try NDJSONCodec.encodeLine(EngineRequest.stop)
        #expect(String(data: start, encoding: .utf8) == "{\"op\":\"start\"}\n")
        #expect(String(data: stop, encoding: .utf8) == "{\"op\":\"stop\"}\n")
    }

    @Test func submitStartAndStopOverFakeSocket() throws {
        let socketURL = uniqueSocketURL()
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
        defer { server.stop() }

        try EngineClient.submit(.start, socketURL: socketURL)
        #expect(engine.currentStatus().state == .starting)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        try EngineClient.submit(.stop, socketURL: socketURL)
        #expect(engine.currentStatus().state == .stopping)
    }

    @Test func imageListConflictsWhenClusterStopped() throws {
        let socketURL = uniqueSocketURL()
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: ClusterEngine(scheduler: ManualEngineScheduler(), images: FakeNodeImageRuntime()),
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
        defer { server.stop() }

        #expect(throws: CLIError.engineError(.conflict)) {
            try EngineClient.listImages(socketURL: socketURL, timeout: timeval(tv_sec: 2, tv_usec: 0))
        }
        #expect(throws: CLIError.engineError(.conflict)) {
            try EngineClient.pruneImages(socketURL: socketURL, timeout: timeval(tv_sec: 2, tv_usec: 0))
        }
    }

    @Test func imageListLoadPruneOverFakeSocket() async throws {
        let socketURL = uniqueSocketURL()
        let scheduler = ManualEngineScheduler()
        let images = FakeNodeImageRuntime()
        let engine = ClusterEngine(scheduler: scheduler, images: images)
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
        defer { server.stop() }

        try EngineClient.submit(.start, socketURL: socketURL)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)

        let empty = try EngineClient.listImages(socketURL: socketURL, timeout: timeval(tv_sec: 2, tv_usec: 0))
        #expect(empty.items.isEmpty)
        #expect(ImageText.renderList(empty) == "No node images.")

        let tar = FileManager.default.temporaryDirectory.appending(path: "gmak8-cli-load-\(UUID().uuidString).tar")
        try Data("tiny-oci-tar-body".utf8).write(to: tar)
        defer { try? FileManager.default.removeItem(at: tar) }

        try EngineClient.submit(.loadImage(path: tar.path(percentEncoded: false)), socketURL: socketURL)
        #expect(engine.currentStatus().imageJob != nil)
        scheduler.runNext()
        var spins = 0
        while engine.currentStatus().imageJob != nil && spins < 200 {
            try await Task.sleep(for: .milliseconds(10))
            spins += 1
        }
        #expect(engine.currentStatus().imageJob == nil)
        #expect(engine.currentStatus().lastError == nil)

        let listed = try EngineClient.listImages(socketURL: socketURL, timeout: timeval(tv_sec: 2, tv_usec: 0))
        #expect(listed.items.contains { $0.refs.contains("nginx:dev") })
        #expect(ImageText.renderList(listed).contains("nginx:dev"))

        let pruned = try EngineClient.pruneImages(socketURL: socketURL, timeout: timeval(tv_sec: 2, tv_usec: 0))
        #expect(pruned.items.isEmpty)
        #expect(images.pruneCount == 1)
    }

    @Test func imageListMissingSocketIsEngineNotRunning() {
        let url = URL(fileURLWithPath: "/tmp/gmak8-missing-\(UUID().uuidString).sock")
        #expect(throws: CLIError.engineNotRunning) {
            try EngineClient.listImages(socketURL: url)
        }
        #expect(throws: CLIError.engineNotRunning) {
            try EngineClient.pruneImages(socketURL: url)
        }
    }

    @Test func subscribeStreamsInitialStatus() async throws {
        let socketURL = uniqueSocketURL()
        let engine = ClusterEngine(scheduler: ManualEngineScheduler())
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
        defer { server.stop() }

        let box = SubscribeBox()
        let status: EngineStatus? = await withCheckedContinuation { continuation in
            box.finish = continuation
            do {
                box.subscription = try EngineClient.subscribe(
                    socketURL: socketURL,
                    timeout: timeval(tv_sec: 2, tv_usec: 0),
                    onEvent: { event in
                        if case .status(let status) = event {
                            box.resume(status)
                        }
                    },
                    onError: { _ in
                        box.resume(nil)
                    }
                )
            } catch {
                box.resume(nil)
            }
        }
        defer { box.subscription?.cancel() }
        #expect(status?.state == .stopped)
    }

    private func uniqueSocketURL() -> URL {
        URL(fileURLWithPath: "/tmp/g8-cli-\(getpid())-\(UUID().uuidString.prefix(8)).sock")
    }

    private func utf8Line<T: Encodable>(_ value: T) throws -> String {
        let data = try NDJSONCodec.encodeLine(value)
        let text = String(data: data, encoding: .utf8)
        try #require(text != nil)
        return text!
    }
}

private final class SubscribeBox: @unchecked Sendable {
    private let lock = NSLock()
    var subscription: EngineSubscription?
    var finish: CheckedContinuation<EngineStatus?, Never>?

    func resume(_ status: EngineStatus?) {
        lock.lock()
        let continuation = finish
        finish = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }
}
