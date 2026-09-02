import Foundation

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
    private let lock = NSLock()
    private let scheduler: any EngineScheduler
    private let nestedVirt: Bool
    private let runtime: any VirtualMachineRuntime

    private var state: ClusterState = .stopped
    private var step: String?
    private var lastError: String?
    private var generation: UInt64 = 0
    private var subscribers: [UUID: @Sendable (EngineEvent) -> Void] = [:]

    public init(
        scheduler: any EngineScheduler,
        nestedVirt: Bool = false,
        runtime: any VirtualMachineRuntime = FakeVirtualMachineRuntime()
    ) {
        self.scheduler = scheduler
        self.nestedVirt = nestedVirt
        self.runtime = runtime
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
        case .stop, .prepareUpdate:
            let logLine = request == .prepareUpdate ? "prepareUpdate" : "stop accepted"
            return requestStopLocked(logLine: logLine, work: &work, events: &events)
        case .reset(let force):
            if !force {
                return .error(.confirmationRequired)
            }
            return requestStopLocked(logLine: "reset", work: &work, events: &events)
        case .status, .subscribe:
            return .ok
        }
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
            }
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
        runtime.stop { [weak self] result in
            self?.completeStop(generation: generation, result: result)
        }
    }

    private func completeStart(generation: UInt64, result: Result<Void, any Error>) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            switch result {
            case .success:
                state = .running
                step = runtime.stepName
                lastError = nil
                events.append(.status(currentStatusLocked()))
                let line = runtime.stepName == "fakeVM" ? "fake VM running" : "VM running"
                events.append(.log(source: .engine, line: line))
            case .failure(let error):
                state = .failed
                lastError = error.localizedDescription
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: error.localizedDescription))
            }
        }
        broadcast(events)
    }

    private func completeStop(generation: UInt64, result: Result<Void, any Error>) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .stopping else {
                return
            }
            switch result {
            case .success:
                state = .stopped
                step = nil
                lastError = nil
            case .failure(let error):
                state = .failed
                lastError = error.localizedDescription
            }
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: "stopped"))
        }
        broadcast(events)
    }

    private func handleDegraded(_ message: String) {
        var events: [EngineEvent] = []
        withLock {
            switch state {
            case .running, .degraded:
                state = .degraded
                lastError = message
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: message))
            case .starting:
                lastError = message
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: message))
            case .stopped, .stopping, .paused, .failed:
                break
            }
        }
        broadcast(events)
    }

    private func handleUnexpectedStop(_ error: Error?) {
        var events: [EngineEvent] = []
        withLock {
            switch state {
            case .running, .starting, .degraded, .paused:
                generation += 1
                if let error {
                    state = .failed
                    lastError = error.localizedDescription
                } else {
                    state = .stopped
                    step = nil
                    lastError = nil
                }
                events.append(.status(currentStatusLocked()))
                events.append(
                    .log(
                        source: .engine,
                        line: error?.localizedDescription ?? "guest stopped"
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
            apiEndpoint: nil,
            vm: VMMetrics(),
            nestedVirt: nestedVirt,
            lastError: lastError,
            publishedPorts: [],
            imageJob: nil
        )
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
