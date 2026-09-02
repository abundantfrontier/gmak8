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

    @Test func statusOverFakeSocketUsesSameCodec() throws {
        let socketURL = URL(fileURLWithPath: "/tmp/g8-cli-\(getpid())-\(UUID().uuidString.prefix(8)).sock")
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

    private func utf8Line<T: Encodable>(_ value: T) throws -> String {
        let data = try NDJSONCodec.encodeLine(value)
        let text = String(data: data, encoding: .utf8)
        try #require(text != nil)
        return text!
    }
}
