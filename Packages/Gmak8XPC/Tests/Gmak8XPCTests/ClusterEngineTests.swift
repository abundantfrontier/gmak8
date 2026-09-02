import Foundation
import Testing

@testable import Gmak8XPC

struct ClusterEngineTests {
    @Test func startStopResetUseFakeVM() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.currentStatus().state == .stopped)

        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().state == .starting)
        #expect(engine.currentStatus().step == "fakeVM")
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)

        #expect(engine.submit(.stop) == .ok)
        #expect(engine.currentStatus().state == .stopping)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
        #expect(engine.currentStatus().step == nil)
    }

    @Test func startWhenStartingOrRunningConflicts() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().state == .starting)
        #expect(engine.submit(.start) == .error(.conflict))
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.submit(.start) == .error(.conflict))
    }

    @Test func resetWithoutForceRequiresConfirmation() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.submit(.reset(force: false)) == .error(.confirmationRequired))
        #expect(engine.currentStatus().state == .starting)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.submit(.reset(force: false)) == .error(.confirmationRequired))
        #expect(engine.currentStatus().state == .running)
    }

    @Test func resetWithForceStopsImmediately() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.submit(.reset(force: true)) == .ok)
        #expect(engine.currentStatus().state == .stopped)
        scheduler.runAll()
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func resetForceCancelsInFlightStart() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.submit(.reset(force: true)) == .ok)
        #expect(engine.currentStatus().state == .stopped)
        scheduler.runAll()
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func stopFromStoppedIsIdempotent() {
        let engine = ClusterEngine(scheduler: ManualEngineScheduler())
        #expect(engine.submit(.stop) == .ok)
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func prepareUpdateReturnsImmediately() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.submit(.prepareUpdate) == .ok)
        #expect(engine.currentStatus().state == .stopping)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func subscribeStreamsStatusAndLogs() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        let box = EventBox()
        let id = engine.subscribe { event in
            box.append(event)
        }
        #expect(box.events.count == 1)
        #expect(statusStates(box.events) == [.stopped])

        #expect(engine.submit(.start) == .ok)
        #expect(statusStates(box.events) == [.stopped, .starting])
        #expect(
            box.events.contains { event in
                if case .log(let source, let line) = event {
                    return source == .engine && line == "start accepted"
                }
                return false
            })

        scheduler.runNext()
        #expect(statusStates(box.events).last == .running)

        engine.unsubscribe(id)
        #expect(engine.submit(.stop) == .ok)
        #expect(statusStates(box.events).last == .running)
    }

    @Test func opsReturnWithoutWaitingForRunning() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().state == .starting)
        #expect(scheduler.pendingCount == 1)
    }

    private func statusStates(_ events: [EngineEvent]) -> [ClusterState] {
        events.compactMap { event in
            if case .status(let status) = event {
                return status.state
            }
            return nil
        }
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [EngineEvent] = []

    var events: [EngineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: EngineEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}
