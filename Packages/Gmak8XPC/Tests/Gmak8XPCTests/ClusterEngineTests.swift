import Foundation
import Gmak8GuestClient
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
        #expect(engine.currentStatus().publishedPorts.isEmpty)

        #expect(engine.submit(.stop) == .ok)
        #expect(engine.currentStatus().state == .stopping)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
        #expect(engine.currentStatus().step == nil)
    }

    @Test func nestedVirtCapabilityIsReportedSeparatelyFromGuestKvm() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler, nestedVirt: true)
        #expect(engine.currentStatus().nestedVirt)
        #expect(engine.currentStatus().kvmPresent == nil)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.currentStatus().nestedVirt)
        #expect(engine.currentStatus().kvmPresent == nil)
        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().kvmPresent == nil)
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

    @Test func prepareUpdateExitsCoreAfterStop() {
        let scheduler = ManualEngineScheduler()
        let processExit = RecordingProcessExit()
        let engine = ClusterEngine(scheduler: scheduler, processExit: processExit)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.submit(.prepareUpdate) == .ok)
        #expect(processExit.codes.isEmpty)
        #expect(engine.currentStatus().state == .stopping)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
        #expect(processExit.codes == [0])
    }

    @Test func prepareUpdateFromStoppedExitsCore() {
        let scheduler = ManualEngineScheduler()
        let processExit = RecordingProcessExit()
        let engine = ClusterEngine(scheduler: scheduler, processExit: processExit)
        #expect(engine.submit(.prepareUpdate) == .ok)
        #expect(engine.currentStatus().state == .stopped)
        #expect(processExit.codes.isEmpty)
        scheduler.runNext()
        #expect(processExit.codes == [0])
    }

    @Test func stopDoesNotExitCore() {
        let scheduler = ManualEngineScheduler()
        let processExit = RecordingProcessExit()
        let engine = ClusterEngine(scheduler: scheduler, processExit: processExit)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
        #expect(processExit.codes.isEmpty)
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

    @Test func stopDuringPrepareDoesNotStartVM() {
        let scheduler = ManualEngineScheduler()
        let runtime = BlockingPrepareRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)

        let startWork = DispatchGroup()
        startWork.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            scheduler.runNext()
            startWork.leave()
        }
        runtime.waitUntilPrepareEntered()
        #expect(engine.submit(.stop) == .ok)
        #expect(engine.currentStatus().state == .stopping)
        runtime.allowPrepareToFinish()
        startWork.wait()
        #expect(!runtime.didStartVM)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .stopped)
        #expect(runtime.stopCount == 1)
    }

    @Test func concurrentStartDoesNotStopTheWinner() {
        let scheduler = ManualEngineScheduler()
        let runtime = BlockingPreflightRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)

        let firstStart = DispatchGroup()
        firstStart.enter()
        let firstReply = ReplyBox()
        DispatchQueue.global(qos: .userInitiated).async {
            firstReply.value = engine.submit(.start)
            firstStart.leave()
        }
        runtime.waitUntilPreflightEntered()
        #expect(engine.submit(.start) == .error(.conflict))
        #expect(runtime.stopCount == 0)
        runtime.allowPreflightToFinish()
        firstStart.wait()
        #expect(firstReply.value == .ok)
        #expect(engine.currentStatus().state == .starting)
        #expect(runtime.stopCount == 0)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(runtime.stopCount == 0)
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

    @Test func unexpectedGuestStopDuringStartLeavesFailedStatus() {
        let scheduler = ManualEngineScheduler()
        let runtime = StubVirtualMachineRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().state == .starting)
        runtime.fireUnexpectedStop(nil)
        #expect(engine.currentStatus().state == .failed)
        #expect(engine.currentStatus().lastError == ClusterEngine.guestStoppedDuringStartMessage)
        #expect(engine.submit(.start) == .ok)
    }

    @Test func gvproxyRestartMarksRunningClusterDegraded() {
        let scheduler = ManualEngineScheduler()
        let runtime = StubVirtualMachineRuntime()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        let message = "gvproxy restarted; guest overlay datapath may be dead"
        runtime.fireDegraded(message)
        #expect(engine.currentStatus().state == .degraded)
        #expect(engine.currentStatus().lastError == message)
    }

    @Test func loadImageConflictsWhenStopped() {
        let engine = ClusterEngine(scheduler: ManualEngineScheduler())
        #expect(engine.submit(.loadImage(path: "/tmp/foo.tar")) == .error(.conflict))
        #expect(engine.currentStatus().lastError == "cluster is not running")
    }

    @Test func portForwardStartsOnlyWhenRunningAndRejectsPod() {
        let scheduler = ManualEngineScheduler()
        let forwards = RecordingPortForwardRuntime()
        let engine = ClusterEngine(scheduler: scheduler, portForwards: forwards)
        #expect(
            engine.submit(
                .portForwardStart(
                    kind: .vm, namespace: "default", name: "build", local: 2222, remote: 22)
            ) == .error(.conflict, message: PortForwardError.notRunning.errorDescription)
        )
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(
            engine.submit(
                .portForwardStart(
                    kind: .pod, namespace: "default", name: "x", local: 18080, remote: 8080)
            ) == .error(.invalidRequest, message: PortForwardError.unsupportedKind(.pod).errorDescription)
        )
        #expect(
            engine.submit(
                .portForwardStart(
                    kind: .vm, namespace: "default", name: "build", local: 22, remote: 22)
            ) == .error(.invalidRequest, message: PortForwardError.forbiddenHostPort(22).errorDescription)
        )
        let reply = engine.submit(
            .portForwardStart(
                kind: .vmi, namespace: "kubevirt", name: "fedora", local: 2222, remote: 22)
        )
        #expect(reply == .started(id: "pf-1"))
        #expect(forwards.sessions.count == 1)
        #expect(forwards.argumentLog[0].contains("--address"))
        #expect(forwards.argumentLog[0].contains("127.0.0.1"))
        #expect(!forwards.argumentLog[0].contains { $0.contains("0.0.0.0") })
        #expect(engine.submit(.portForwardStop(id: "pf-1")) == .ok)
        #expect(forwards.sessions.isEmpty)
        #expect(
            engine.submit(
                .portForwardStart(
                    kind: .vm, namespace: "default", name: "build", local: 2222, remote: 22)
            ) == .started(id: "pf-2")
        )
        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(forwards.stopAllCount == 1)
        #expect(forwards.sessions.isEmpty)
    }

    @Test func portForwardWithoutVirtctlIsUnavailable() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(
            engine.submit(
                .portForwardStart(
                    kind: .vm, namespace: "default", name: "build", local: 2222, remote: 22)
            ) == .error(.unavailable, message: PortForwardError.virtctlMissing.errorDescription)
        )
    }

    @Test func loadImageRejectsMissingPath() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.submit(.loadImage(path: "")) == .error(.invalidRequest))
        #expect(
            engine.submit(.loadImage(path: "/tmp/gmak8-missing-\(UUID().uuidString).tar"))
                == .error(.invalidRequest)
        )
    }

    @Test func imagePreflightAddsTwentyPercent() {
        #expect(ImagePreflight.bytesNeeded(fileSize: 100) == 120)
        #expect(ImagePreflight.hasRoom(fileSize: 100, bytesFree: 120))
        #expect(!ImagePreflight.hasRoom(fileSize: 100, bytesFree: 119))
    }

    @Test func loadImageImportsViaRuntimeAndClearsJob() async throws {
        let scheduler = ManualEngineScheduler()
        let runtime = FakeNodeImageRuntime()
        let engine = ClusterEngine(scheduler: scheduler, images: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)

        let tar = FileManager.default.temporaryDirectory.appending(path: "gmak8-load-\(UUID().uuidString).tar")
        try Data("tiny-oci-tar-body".utf8).write(to: tar)
        defer { try? FileManager.default.removeItem(at: tar) }

        #expect(engine.submit(.loadImage(path: tar.path(percentEncoded: false))) == .ok)
        #expect(engine.currentStatus().imageJob != nil)
        scheduler.runNext()
        var spins = 0
        while engine.currentStatus().imageJob != nil && spins < 200 {
            try await Task.sleep(for: .milliseconds(10))
            spins += 1
        }
        #expect(engine.currentStatus().imageJob == nil)
        #expect(engine.currentStatus().lastError == nil)
        #expect(runtime.importedURLs.count == 1)
        let listed = try await engine.listImages()
        #expect(listed.items.contains { $0.refs.contains("nginx:dev") })
    }

    @Test func loadImageFailsPreflightWhenDiskIsTight() async throws {
        let scheduler = ManualEngineScheduler()
        let runtime = FakeNodeImageRuntime()
        runtime.disksValue = GuestDisks(
            gmak8Data: .mounted,
            kiteData: .mounted,
            mountpoint: "/mnt/data",
            label: "GMAK8_DATA",
            bytesTotal: 100,
            bytesFree: 1
        )
        let engine = ClusterEngine(scheduler: scheduler, images: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()

        let tar = FileManager.default.temporaryDirectory.appending(path: "gmak8-load-\(UUID().uuidString).tar")
        try Data("tiny-oci-tar-body".utf8).write(to: tar)
        defer { try? FileManager.default.removeItem(at: tar) }

        #expect(engine.submit(.loadImage(path: tar.path(percentEncoded: false))) == .ok)
        scheduler.runNext()
        var spins = 0
        while engine.currentStatus().imageJob != nil && spins < 200 {
            try await Task.sleep(for: .milliseconds(10))
            spins += 1
        }
        #expect(engine.currentStatus().imageJob == nil)
        #expect(engine.currentStatus().lastError?.contains("20%") == true)
        #expect(runtime.importedURLs.isEmpty)
    }

    @Test func listImagesMapsMissingGuestEndpoint() async throws {
        let scheduler = ManualEngineScheduler()
        let runtime = FakeNodeImageRuntime()
        runtime.listError = ClusterBringUpError(message: NodeImageErrors.guestMissingImages)
        let engine = ClusterEngine(scheduler: scheduler, images: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        do {
            _ = try await engine.listImages()
            Issue.record("expected list failure")
        } catch let error as ClusterBringUpError {
            #expect(error.message == NodeImageErrors.guestMissingImages)
        }
        #expect(
            NodeImageErrors.message(from: GuestAgentError.httpStatus(404, nil))
                == NodeImageErrors.guestMissingImages)
    }

    @Test func secondLoadImageConflictsWhileJobRuns() throws {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler, images: FakeNodeImageRuntime())
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        let tar = FileManager.default.temporaryDirectory.appending(path: "gmak8-load-\(UUID().uuidString).tar")
        try Data("tiny-oci-tar-body".utf8).write(to: tar)
        defer { try? FileManager.default.removeItem(at: tar) }
        #expect(engine.submit(.loadImage(path: tar.path(percentEncoded: false))) == .ok)
        #expect(engine.submit(.loadImage(path: tar.path(percentEncoded: false))) == .error(.conflict))
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

    private var degradedHandler: (@Sendable (String) -> Void)?

    func setDegradedHandler(_ handler: (@Sendable (String) -> Void)?) {
        degradedHandler = handler
    }

    func fireDegraded(_ message: String) {
        degradedHandler?(message)
    }
}

private final class BlockingPrepareRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    var didStartVM = false
    var stopCount = 0
    private let lock = NSCondition()
    private var prepareEntered = false
    private var allowPrepare = false
    private var cancelled = false

    func preflight() -> VirtualMachinePreflightError? {
        nil
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        lock.lock()
        prepareEntered = true
        lock.broadcast()
        while !allowPrepare && !cancelled {
            lock.wait()
        }
        let abort = cancelled
        lock.unlock()
        if abort {
            completion(.failure(EngineErrorCode.conflict))
            return
        }
        didStartVM = true
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        stopCount += 1
        completion(.success(()))
    }

    func cancelInFlightStart() {
        lock.lock()
        cancelled = true
        lock.broadcast()
        lock.unlock()
    }

    func waitUntilPrepareEntered() {
        lock.lock()
        let deadline = Date().addingTimeInterval(5)
        while !prepareEntered {
            if !lock.wait(until: deadline) {
                break
            }
        }
        lock.unlock()
    }

    func allowPrepareToFinish() {
        lock.lock()
        allowPrepare = true
        lock.broadcast()
        lock.unlock()
    }
}

private final class BlockingPreflightRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    var stopCount = 0
    private let lock = NSCondition()
    private var preflightEntered = false
    private var allowPreflight = false

    func preflight() -> VirtualMachinePreflightError? {
        lock.lock()
        preflightEntered = true
        lock.broadcast()
        while !allowPreflight {
            lock.wait()
        }
        lock.unlock()
        return nil
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        stopCount += 1
        completion(.success(()))
    }

    func waitUntilPreflightEntered() {
        lock.lock()
        let deadline = Date().addingTimeInterval(5)
        while !preflightEntered {
            if !lock.wait(until: deadline) {
                break
            }
        }
        lock.unlock()
    }

    func allowPreflightToFinish() {
        lock.lock()
        allowPreflight = true
        lock.broadcast()
        lock.unlock()
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

private final class RecordingProcessExit: ProcessExiting, @unchecked Sendable {
    var codes: [Int32] = []

    func exitProcess(code: Int32) {
        codes.append(code)
    }
}

private final class ReplyBox: @unchecked Sendable {
    var value: EngineReply?
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
