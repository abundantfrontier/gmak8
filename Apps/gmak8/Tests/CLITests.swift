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
