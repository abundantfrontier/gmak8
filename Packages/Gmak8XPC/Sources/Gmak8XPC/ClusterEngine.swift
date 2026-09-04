import Foundation
import Gmak8GuestClient

public protocol EngineScheduler: Sendable {
    func schedule(_ work: @escaping @Sendable () -> Void)
}

public struct DispatchEngineScheduler: EngineScheduler, Sendable {
    public var nanoseconds: UInt64

    public init(nanoseconds: UInt64 = 50_000_000) {
        self.nanoseconds = nanoseconds
    }

    public func schedule(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .nanoseconds(Int(nanoseconds)),
            execute: work
        )
    }
}

/// Holds fake-VM transitions until the test pumps them. Production uses `DispatchEngineScheduler`.
public final class ManualEngineScheduler: EngineScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () -> Void] = []

    public init() {}

    public func schedule(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        pending.append(work)
        lock.unlock()
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    public func runNext() {
        lock.lock()
        guard !pending.isEmpty else {
            lock.unlock()
            return
        }
        let work = pending.removeFirst()
        lock.unlock()
        work()
    }

    public func runAll() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                lock.unlock()
                return
            }
            let work = pending.removeFirst()
            lock.unlock()
            work()
        }
    }
}

public final class ClusterEngine: @unchecked Sendable {
    public static let guestStoppedDuringStartMessage =
        "Virtual machine stopped before the guest was ready."

    private let lock = NSLock()
    private let scheduler: any EngineScheduler
    private let nestedVirt: Bool
    private var guestKvm: Bool?
    private let runtime: any VirtualMachineRuntime
    private let bringUp: any ClusterBringUp
    private let publisher: any PortPublisher
    private let diskReset: any ClusterDiskResetting
    private let processExit: any ProcessExiting
    private let images: any NodeImageRuntime
    private let portForwards: any PortForwardRuntime
    private let fileManager: FileManager

    private var state: ClusterState = .stopped
    private var step: String?
    private var lastError: String?
    private var apiEndpoint: String?
    private var failAfterStop: String?
    private var wipeDisksAfterStop = false
    private var exitAfterStop = false
    private var generation: UInt64 = 0
    private var imageJob: ImageJobStatus?
    private var subscribers: [UUID: @Sendable (EngineEvent) -> Void] = [:]

    public init(
        scheduler: any EngineScheduler,
        nestedVirt: Bool = false,
        runtime: any VirtualMachineRuntime = FakeVirtualMachineRuntime(),
        bringUp: any ClusterBringUp = NoOpClusterBringUp(),
        publisher: any PortPublisher = NoOpPortPublisher(),
        diskReset: any ClusterDiskResetting = NoOpClusterDiskReset(),
        processExit: any ProcessExiting = NoProcessExit(),
        images: any NodeImageRuntime = NoOpNodeImageRuntime(),
        portForwards: any PortForwardRuntime = NoOpPortForwardRuntime(),
        fileManager: FileManager = .default
    ) {
        self.scheduler = scheduler
        self.nestedVirt = nestedVirt
        self.runtime = runtime
        self.bringUp = bringUp
        self.publisher = publisher
        self.diskReset = diskReset
        self.processExit = processExit
        self.images = images
        self.portForwards = portForwards
        self.fileManager = fileManager
        self.runtime.setUnexpectedStopHandler { [weak self] error in
            self?.handleUnexpectedStop(error)
        }
        self.runtime.setDegradedHandler { [weak self] message in
            self?.handleDegraded(message)
        }
    }

    public func currentStatus() -> EngineStatus {
        withLock { currentStatusLocked() }
    }

    public func submit(_ request: EngineRequest) -> EngineReply {
        if case .start = request {
            return submitStart()
        }
        var work: (@Sendable () -> Void)?
        var events: [EngineEvent] = []
        let reply = withLock { handleLocked(request, work: &work, events: &events) }
        broadcast(events)
        if let work {
            scheduler.schedule(work)
        }
        return reply
    }

    @discardableResult
    public func subscribe(_ handler: @escaping @Sendable (EngineEvent) -> Void) -> UUID {
        let id = UUID()
        let snapshot: EngineEvent = withLock {
            subscribers[id] = handler
            return .status(currentStatusLocked())
        }
        handler(snapshot)
        return id
    }

    public func unsubscribe(_ id: UUID) {
        withLock { _ = subscribers.removeValue(forKey: id) }
    }

    private func submitStart() -> EngineReply {
        var events: [EngineEvent] = []
        var claimedGeneration: UInt64 = 0
        let conflict = withLock {
            switch state {
            case .starting, .running, .degraded, .paused, .stopping:
                return true
            case .stopped, .failed:
                state = .starting
                step = runtime.stepName
                lastError = nil
                apiEndpoint = nil
                failAfterStop = nil
                wipeDisksAfterStop = false
                exitAfterStop = false
                imageJob = nil
                generation += 1
                claimedGeneration = generation
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: "start accepted"))
                return false
            }
        }
        if conflict {
            return .error(.conflict)
        }
        let gen = claimedGeneration
        broadcast(events)
        events = []

        if let failure = runtime.preflight() {
            var reply = EngineReply.error(failure.code)
            withLock {
                guard generation == gen, state == .starting else {
                    reply = .ok
                    return
                }
                state = .stopped
                step = nil
                lastError = failure.message
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: failure.message))
            }
            if case .error = reply {
                runtime.stop { _ in }
            }
            broadcast(events)
            return reply
        }

        var work: (@Sendable () -> Void)?
        withLock {
            guard generation == gen, state == .starting else {
                return
            }
            work = { [weak self] in
                self?.beginStart(generation: gen)
            }
        }
        if let work {
            scheduler.schedule(work)
        }
        return .ok
    }

    private func handleLocked(
        _ request: EngineRequest,
        work: inout (@Sendable () -> Void)?,
        events: inout [EngineEvent]
    ) -> EngineReply {
        switch request {
        case .start:
            return .error(.invalidRequest)
        case .stop:
            return requestStopLocked(logLine: "stop accepted", work: &work, events: &events)
        case .prepareUpdate:
            exitAfterStop = true
            let reply = requestStopLocked(logLine: "prepareUpdate", work: &work, events: &events)
            if state == .stopped && work == nil {
                work = { [weak self] in
                    self?.finishPrepareUpdateExit()
                }
            }
            return reply
        case .reset(let force):
            if !force {
                return .error(.confirmationRequired)
            }
            wipeDisksAfterStop = true
            switch state {
            case .stopped:
                events.append(.log(source: .engine, line: "reset"))
                work = { [weak self] in
                    self?.performDiskReset()
                }
                return .ok
            case .stopping:
                events.append(.log(source: .engine, line: "reset"))
                return .ok
            case .starting, .running, .degraded, .paused, .failed:
                return requestStopLocked(logLine: "reset", work: &work, events: &events)
            }
        case .status, .subscribe:
            return .ok
        case .loadImage(let path):
            return requestLoadImageLocked(path: path, work: &work, events: &events)
        case .imageList, .imagePrune:
            return .ok
        case .portForwardStart(let kind, let namespace, let name, let local, let remote):
            return startPortForwardLocked(
                kind: kind, namespace: namespace, name: name, local: local, remote: remote, events: &events)
        case .portForwardStop(let id):
            return stopPortForwardLocked(id: id, events: &events)
        }
    }

    private func startPortForwardLocked(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int,
        events: inout [EngineEvent]
    ) -> EngineReply {
        switch state {
        case .running, .degraded:
            break
        default:
            return .error(.conflict, message: PortForwardError.notRunning.errorDescription)
        }
        do {
            let session = try portForwards.start(
                kind: kind, namespace: namespace, name: name, local: local, remote: remote)
            events.append(
                .log(
                    source: .engine,
                    line:
                        "port-forward \(session.id) \(session.kind.rawValue)/\(session.name) \(session.address):\(session.local)->\(session.remote)"
                )
            )
            return .started(id: session.id)
        } catch let error as PortForwardError {
            return portForwardReply(error)
        } catch {
            return .error(.invalidRequest, message: error.localizedDescription)
        }
    }

    private func stopPortForwardLocked(id: String, events: inout [EngineEvent]) -> EngineReply {
        do {
            try portForwards.stop(id: id)
            events.append(.log(source: .engine, line: "port-forward stop \(id)"))
            return .ok
        } catch let error as PortForwardError {
            return portForwardReply(error)
        } catch {
            return .error(.invalidRequest, message: error.localizedDescription)
        }
    }

    private func portForwardReply(_ error: PortForwardError) -> EngineReply {
        let message = error.errorDescription
        switch error {
        case .notRunning:
            return .error(.conflict, message: message)
        case .virtctlMissing:
            return .error(.unavailable, message: message)
        case .forbiddenHostPort, .invalidPort, .invalidTarget, .unsupportedKind:
            return .error(.invalidRequest, message: message)
        }
    }

    public func listImages() async throws -> NodeImageList {
        try requireImagesReady()
        do {
            let items = try await images.list()
            return NodeImageList(items: NodeImageMapping.nodeImages(items))
        } catch let code as EngineErrorCode {
            throw code
        } catch {
            throw ClusterBringUpError(message: NodeImageErrors.message(from: error))
        }
    }

    public func pruneImages() async throws -> NodeImageList {
        try requireImagesReady()
        do {
            _ = try await images.prune()
            let items = try await images.list()
            let list = NodeImageList(items: NodeImageMapping.nodeImages(items))
            broadcast([
                .log(source: .engine, line: "pruned images"),
                .images(list),
            ])
            return list
        } catch let code as EngineErrorCode {
            throw code
        } catch {
            throw ClusterBringUpError(message: NodeImageErrors.message(from: error))
        }
    }

    private func requireImagesReady() throws {
        let ready = withLock {
            switch state {
            case .running, .degraded:
                return true
            case .stopped, .starting, .paused, .stopping, .failed:
                return false
            }
        }
        if !ready {
            throw EngineErrorCode.conflict
        }
    }

    private func requestLoadImageLocked(
        path: String,
        work: inout (@Sendable () -> Void)?,
        events: inout [EngineEvent]
    ) -> EngineReply {
        switch state {
        case .running, .degraded:
            break
        case .stopped, .starting, .paused, .stopping, .failed:
            lastError = "cluster is not running"
            events.append(.status(currentStatusLocked()))
            return .error(.conflict)
        }
        if imageJob != nil {
            return .error(.conflict)
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "image path is required"
            events.append(.status(currentStatusLocked()))
            return .error(.invalidRequest)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trimmed, isDirectory: &isDirectory), !isDirectory.boolValue else {
            lastError = "image tar not found"
            events.append(.status(currentStatusLocked()))
            return .error(.invalidRequest)
        }
        let attrs = try? fileManager.attributesOfItem(atPath: trimmed)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            lastError = "image tar is empty"
            events.append(.status(currentStatusLocked()))
            return .error(.invalidRequest)
        }
        lastError = nil
        imageJob = ImageJobStatus(bytesReceived: 0, bytesTotal: size)
        events.append(.status(currentStatusLocked()))
        events.append(.log(source: .engine, line: "loadImage accepted"))
        work = { [weak self] in
            self?.beginLoadImage(path: trimmed, size: size)
        }
        return .ok
    }

    private func beginLoadImage(path: String, size: Int64) {
        Task { [weak self] in
            await self?.performLoadImage(path: path, size: size)
        }
    }

    private func performLoadImage(path: String, size: Int64) async {
        do {
            let disks = try await images.disks()
            guard disks.isDataMounted else {
                failLoadImage("data disk is not mounted")
                return
            }
            guard ImagePreflight.hasRoom(fileSize: size, bytesFree: disks.bytesFree) else {
                failLoadImage(
                    "data disk has \(disks.bytesFree) bytes free; image import needs \(ImagePreflight.bytesNeeded(fileSize: size)) (archive + 20%)"
                )
                return
            }
            let url = URL(fileURLWithPath: path)
            let result = try await images.importImage(
                fileURL: url,
                name: url.lastPathComponent
            ) { [weak self] received, total in
                let importing = total > 0 && received >= total
                self?.setUserImageJob(
                    ImageJobStatus(bytesReceived: received, bytesTotal: total, importing: importing)
                )
            }
            var listed: NodeImageList = NodeImageList()
            if let items = try? await images.list() {
                listed = NodeImageList(items: NodeImageMapping.nodeImages(items))
            }
            finishLoadImage(
                result: result,
                list: listed
            )
        } catch {
            failLoadImage(error.localizedDescription)
        }
    }

    private func setUserImageJob(_ job: ImageJobStatus?) {
        var events: [EngineEvent] = []
        withLock {
            switch state {
            case .running, .degraded:
                imageJob = job
                events.append(.status(currentStatusLocked()))
            case .stopped, .starting, .paused, .stopping, .failed:
                break
            }
        }
        broadcast(events)
    }

    private func failLoadImage(_ message: String) {
        var events: [EngineEvent] = []
        withLock {
            imageJob = nil
            lastError = message
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: message))
        }
        broadcast(events)
    }

    private func finishLoadImage(result: GuestImageImport, list: NodeImageList) {
        var events: [EngineEvent] = []
        withLock {
            imageJob = nil
            switch state {
            case .running, .degraded:
                lastError = nil
                events.append(.status(currentStatusLocked()))
                var line = "imported"
                if !result.digest.isEmpty {
                    line += " \(result.digest)"
                }
                if let ref = result.refs.first {
                    line += " \(ref)"
                }
                events.append(.log(source: .engine, line: line))
                events.append(.images(list))
            case .stopped, .starting, .paused, .stopping, .failed:
                events.append(.status(currentStatusLocked()))
            }
        }
        broadcast(events)
    }

    private func requestStopLocked(
        logLine: String,
        work: inout (@Sendable () -> Void)?,
        events: inout [EngineEvent]
    ) -> EngineReply {
        switch state {
        case .stopped:
            events.append(.log(source: .engine, line: logLine))
            return .ok
        case .stopping:
            events.append(.log(source: .engine, line: logLine))
            return .ok
        case .starting, .running, .degraded, .paused, .failed:
            let cancelStart = state == .starting
            state = .stopping
            step = runtime.stepName
            generation += 1
            let gen = generation
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: logLine))
            if cancelStart {
                runtime.cancelInFlightStart()
                bringUp.cancel()
            }
            portForwards.stopAll()
            work = { [weak self] in
                self?.beginStop(generation: gen)
            }
            return .ok
        }
    }

    private func beginStart(generation: UInt64) {
        let cancelled = withLock { generation != self.generation || state != .starting }
        if cancelled {
            runtime.stop { _ in }
            return
        }
        runtime.start { [weak self] result in
            self?.completeStart(generation: generation, result: result)
        }
    }

    private func beginStop(generation: UInt64) {
        publisher.cancel()
        runtime.stop { [weak self] result in
            self?.completeStop(generation: generation, result: result)
        }
    }

    private func completeStart(generation: UInt64, result: Result<Void, any Error>) {
        var events: [EngineEvent] = []
        var startBringUp = false
        var startPublisher = false
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            switch result {
            case .success:
                if bringUp.isNoOp {
                    state = .running
                    step = runtime.stepName
                    lastError = nil
                    events.append(.status(currentStatusLocked()))
                    let line = runtime.stepName == "fakeVM" ? "fake VM running" : "VM running"
                    events.append(.log(source: .engine, line: line))
                    startPublisher = true
                } else {
                    lastError = nil
                    events.append(.status(currentStatusLocked()))
                    events.append(.log(source: .engine, line: "VM running"))
                    startBringUp = true
                }
            case .failure(let error):
                state = .failed
                lastError = error.localizedDescription
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: error.localizedDescription))
            }
        }
        broadcast(events)
        if startBringUp {
            beginBringUp(generation: generation)
        }
        if startPublisher {
            beginPublisher()
        }
    }

    private func beginBringUp(generation: UInt64) {
        bringUp.start(
            generation: generation,
            isCurrent: { [weak self] gen in
                guard let engine = self else {
                    return false
                }
                return engine.withLock { gen == engine.generation && engine.state == .starting }
            },
            setStep: { [weak self] name in
                self?.updateStep(generation: generation, name: name)
            },
            setImageJob: { [weak self] job in
                self?.updateImageJob(generation: generation, job: job)
            },
            log: { [weak self] line in
                self?.broadcast([.log(source: .engine, line: line)])
            },
            completion: { [weak self] result in
                self?.completeBringUp(generation: generation, result: result)
            }
        )
    }

    private func updateStep(generation: UInt64, name: String) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            step = name
            events.append(.status(currentStatusLocked()))
        }
        broadcast(events)
    }

    private func updateImageJob(generation: UInt64, job: ImageJobStatus?) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            imageJob = job
            events.append(.status(currentStatusLocked()))
        }
        broadcast(events)
    }

    private func completeBringUp(generation: UInt64, result: Result<ClusterBringUpResult, any Error>) {
        var events: [EngineEvent] = []
        var stopGeneration: UInt64?
        var startPublisher = false
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            switch result {
            case .success(let outcome):
                state = .running
                apiEndpoint = outcome.apiEndpoint
                guestKvm = outcome.kvmPresent
                lastError = nil
                imageJob = nil
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: "cluster running"))
                startPublisher = true
            case .failure(let error):
                lastError = error.localizedDescription
                failAfterStop = lastError
                state = .stopping
                step = runtime.stepName
                imageJob = nil
                self.generation += 1
                stopGeneration = self.generation
                bringUp.cancel()
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: error.localizedDescription))
            }
        }
        broadcast(events)
        if startPublisher {
            beginPublisher()
        }
        if let stopGeneration {
            scheduler.schedule { [weak self] in
                self?.beginStop(generation: stopGeneration)
            }
        }
    }

    private func completeStop(generation: UInt64, result: Result<Void, any Error>) {
        var events: [EngineEvent] = []
        var shouldWipe = false
        var shouldExit = false
        withLock {
            guard generation == self.generation, state == .stopping else {
                return
            }
            guestKvm = nil
            switch result {
            case .success:
                if wipeDisksAfterStop {
                    shouldWipe = true
                    wipeDisksAfterStop = false
                    failAfterStop = nil
                    state = .stopped
                    step = nil
                    lastError = nil
                    apiEndpoint = nil
                    imageJob = nil
                } else if let message = failAfterStop {
                    state = .failed
                    lastError = message
                    failAfterStop = nil
                    step = nil
                    apiEndpoint = nil
                    imageJob = nil
                } else {
                    state = .stopped
                    step = nil
                    lastError = nil
                    apiEndpoint = nil
                    imageJob = nil
                }
            case .failure(let error):
                state = .failed
                if failAfterStop == nil {
                    lastError = error.localizedDescription
                } else {
                    lastError = failAfterStop
                    failAfterStop = nil
                }
                apiEndpoint = nil
                imageJob = nil
            }
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: "stopped"))
            if exitAfterStop {
                shouldExit = true
                exitAfterStop = false
            }
        }
        broadcast(events)
        if shouldWipe {
            performDiskReset()
        }
        if shouldExit {
            finishPrepareUpdateExit()
        }
    }

    private func finishPrepareUpdateExit() {
        withLock { exitAfterStop = false }
        processExit.exitProcess(code: 0)
    }

    private func performDiskReset() {
        do {
            try diskReset.resetDisks()
            var events: [EngineEvent] = []
            withLock {
                lastError = nil
                events.append(.log(source: .engine, line: "reset disks"))
                events.append(.status(currentStatusLocked()))
            }
            broadcast(events)
        } catch {
            var events: [EngineEvent] = []
            withLock {
                lastError = error.localizedDescription
                events.append(.log(source: .engine, line: error.localizedDescription))
                events.append(.status(currentStatusLocked()))
            }
            broadcast(events)
        }
    }

    private func handleDegraded(_ message: String) {
        var events: [EngineEvent] = []
        var reexpose = false
        withLock {
            switch state {
            case .running, .degraded:
                state = .degraded
                lastError = message
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: message))
                reexpose = true
            case .starting:
                lastError = message
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: message))
            case .stopped, .stopping, .paused, .failed:
                break
            }
        }
        broadcast(events)
        if reexpose {
            publisher.reexpose()
        }
    }

    private func handleUnexpectedStop(_ error: Error?) {
        publisher.cancel()
        var events: [EngineEvent] = []
        withLock {
            switch state {
            case .running, .starting, .degraded, .paused:
                generation += 1
                if let error {
                    state = .failed
                    lastError = error.localizedDescription
                    apiEndpoint = nil
                    imageJob = nil
                } else if state == .starting {
                    state = .failed
                    lastError = Self.guestStoppedDuringStartMessage
                    apiEndpoint = nil
                    imageJob = nil
                } else {
                    state = .stopped
                    step = nil
                    lastError = nil
                    apiEndpoint = nil
                    imageJob = nil
                }
                events.append(.status(currentStatusLocked()))
                events.append(
                    .log(
                        source: .engine,
                        line: lastError ?? "guest stopped"
                    )
                )
            case .stopped, .stopping, .failed:
                break
            }
        }
        broadcast(events)
    }

    private func currentStatusLocked() -> EngineStatus {
        EngineStatus(
            state: state,
            step: step,
            apiEndpoint: apiEndpoint,
            vm: VMMetrics(),
            nestedVirt: nestedVirt,
            kvmPresent: guestKvm,
            lastError: lastError,
            publishedPorts: publisher.snapshot(),
            imageJob: imageJob
        )
    }

    private func beginPublisher() {
        publisher.start(
            onChange: { [weak self] in
                self?.publishPortsChanged()
            },
            log: { [weak self] line in
                self?.broadcast([.log(source: .engine, line: line)])
            }
        )
    }

    private func publishPortsChanged() {
        var events: [EngineEvent] = []
        withLock {
            switch state {
            case .running, .degraded, .stopping:
                events.append(.status(currentStatusLocked()))
            case .stopped, .starting, .paused, .failed:
                break
            }
        }
        broadcast(events)
    }

    private func broadcast(_ events: [EngineEvent]) {
        guard !events.isEmpty else {
            return
        }
        let handlers: [@Sendable (EngineEvent) -> Void] = withLock { Array(subscribers.values) }
        for event in events {
            for handler in handlers {
                handler(event)
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
