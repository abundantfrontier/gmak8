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

    @Test func resetWithForceWaitsForRuntimeStop() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.submit(.reset(force: true)) == .ok)
        #expect(engine.currentStatus().state == .stopping)
        scheduler.runAll()
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func resetForceCancelsInFlightStart() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.submit(.reset(force: true)) == .ok)
        #expect(engine.currentStatus().state == .stopping)
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

    @Test func startFailsWhenDiskImagesLocked() {
        let runtime = StubVirtualMachineRuntime(
            preflightError: VirtualMachinePreflightError(
                code: .locked,
                message: "Another gmak8 (engine.sock live) holds data.img. Quit that instance."
            )
        )
        let engine = ClusterEngine(scheduler: ManualEngineScheduler(), runtime: runtime)
        #expect(engine.submit(.start) == .error(.locked))
        #expect(engine.currentStatus().state == .stopped)
        #expect(engine.currentStatus().lastError?.contains("data.img") == true)
        #expect(!runtime.started)
    }

    @Test func startFailsUnsupportedWithoutLockCopy() {
        let message =
            "This Mac cannot run a virtual machine (unsupported CPU, OS, or missing virtualization entitlement)."
        let runtime = StubVirtualMachineRuntime(
            preflightError: VirtualMachinePreflightError(
                code: .virtualizationUnsupported,
                message: message
            )
        )
        let engine = ClusterEngine(scheduler: ManualEngineScheduler(), runtime: runtime)
        #expect(engine.submit(.start) == .error(.virtualizationUnsupported))
        #expect(engine.currentStatus().state == .stopped)
        #expect(engine.currentStatus().lastError == message)
        let lastError = engine.currentStatus().lastError ?? ""
        #expect(!lastError.lowercased().contains("lock"))
        #expect(!lastError.lowercased().contains("hypervisor"))
        #expect(!runtime.started)
    }

    @Test func customRuntimeStartAndStopAreInvoked() {
        let scheduler = ManualEngineScheduler()
        let runtime = StubVirtualMachineRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().step == "vm")
        scheduler.runNext()
        #expect(runtime.started)
        #expect(engine.currentStatus().state == .running)
        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(runtime.stopped)
        #expect(engine.currentStatus().state == .stopped)
    }

    @Test func staleStartCompletionDoesNotStopTheNextVM() {
        let scheduler = ManualEngineScheduler()
        let runtime = DeferredStartRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)

        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(runtime.pendingStartCount == 1)

        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(runtime.stopCount == 1)
        #expect(engine.currentStatus().state == .stopped)

        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(runtime.pendingStartCount == 2)

        runtime.finishOldestStart(.success(()))
        #expect(runtime.stopCount == 1)
        #expect(engine.currentStatus().state == .starting)

        runtime.finishOldestStart(.success(()))
        #expect(engine.currentStatus().state == .running)
        #expect(runtime.stopCount == 1)
    }

    @Test func unexpectedGuestStopLeavesEngineStopped() {
        let scheduler = ManualEngineScheduler()
        let runtime = StubVirtualMachineRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        runtime.fireUnexpectedStop(nil)
        #expect(engine.currentStatus().state == .stopped)
        #expect(engine.submit(.start) == .ok)
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

private final class StubVirtualMachineRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    var preflightError: VirtualMachinePreflightError?
    var started = false
    var stopped = false
    private var unexpectedStopHandler: (@Sendable (Error?) -> Void)?

    init(preflightError: VirtualMachinePreflightError? = nil) {
        self.preflightError = preflightError
    }

    func preflight() -> VirtualMachinePreflightError? {
        preflightError
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        started = true
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        stopped = true
        completion(.success(()))
    }

    func setUnexpectedStopHandler(_ handler: (@Sendable (Error?) -> Void)?) {
        unexpectedStopHandler = handler
    }

    func fireUnexpectedStop(_ error: Error?) {
        unexpectedStopHandler?(error)
    }
}

private final class DeferredStartRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    var stopCount = 0
    private var startCompletions: [@Sendable (Result<Void, any Error>) -> Void] = []

    var pendingStartCount: Int { startCompletions.count }

    func preflight() -> VirtualMachinePreflightError? {
        nil
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        startCompletions.append(completion)
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        stopCount += 1
        completion(.success(()))
    }

    func finishOldestStart(_ result: Result<Void, any Error>) {
        guard !startCompletions.isEmpty else {
            return
        }
        let completion = startCompletions.removeFirst()
        completion(result)
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
