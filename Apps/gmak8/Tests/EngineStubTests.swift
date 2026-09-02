import Foundation
import Gmak8XPC
import Testing

struct EngineStubTests {
    @Test func twoLoginItemsCopyNamesAgentAndMenuExtra() {
        let copy = CoreLaunchAgent.twoLoginItemsExplanation
        #expect(copy.contains("two Login Items"))
        #expect(copy.contains("gmak8-core LaunchAgent"))
        #expect(copy.contains("menu extra"))
    }

    @Test func resetRequiresForceAndStartConflicts() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.reset(force: false)) == .error(.confirmationRequired))
        #expect(engine.submit(.start) == .ok)
        #expect(engine.submit(.start) == .error(.conflict))
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.submit(.start) == .error(.conflict))
        #expect(engine.submit(.reset(force: true)) == .ok)
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func translocationRefusesRegisterOutsideApplications() {
        #expect(throws: EngineErrorCode.translocated) {
            try CoreLaunchAgent.register(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app"),
                service: NoopLaunchAgent()
            )
        }
    }

    @Test func startOpEncodesAsNDJSON() throws {
        let data = try NDJSONCodec.encodeLine(EngineRequest.start)
        #expect(String(data: data, encoding: .utf8) == "{\"op\":\"start\"}\n")
    }
}

private struct NoopLaunchAgent: LaunchAgentRegistering {
    func register() throws {}
    func unregister() throws {}
}
