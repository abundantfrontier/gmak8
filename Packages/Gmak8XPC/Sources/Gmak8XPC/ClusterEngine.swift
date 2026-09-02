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

    private var state: ClusterState = .stopped
    private var step: String?
    private var lastError: String?
    private var generation: UInt64 = 0
    private var subscribers: [UUID: @Sendable (EngineEvent) -> Void] = [:]

    public init(scheduler: any EngineScheduler, nestedVirt: Bool = false) {
        self.scheduler = scheduler
        self.nestedVirt = nestedVirt
    }

    public func currentStatus() -> EngineStatus {
        withLock { currentStatusLocked() }
    }

    public func submit(_ request: EngineRequest) -> EngineReply {
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

    private func handleLocked(
        _ request: EngineRequest,
        work: inout (@Sendable () -> Void)?,
        events: inout [EngineEvent]
    ) -> EngineReply {
        switch request {
        case .start:
            switch state {
            case .starting, .running, .degraded, .paused, .stopping:
                return .error(.conflict)
            case .stopped, .failed:
                state = .starting
                step = "fakeVM"
                lastError = nil
                generation += 1
                let gen = generation
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: "start accepted"))
                work = { [weak self] in
                    self?.completeStart(generation: gen)
                }
                return .ok
            }
        case .stop, .prepareUpdate:
            let logLine = request == .prepareUpdate ? "prepareUpdate" : "stop accepted"
            switch state {
            case .stopped:
                events.append(.log(source: .engine, line: logLine))
                return .ok
            case .stopping:
                events.append(.log(source: .engine, line: logLine))
                return .ok
            case .starting, .running, .degraded, .paused, .failed:
                state = .stopping
                step = "fakeVM"
                generation += 1
                let gen = generation
                events.append(.status(currentStatusLocked()))
                events.append(.log(source: .engine, line: logLine))
                work = { [weak self] in
                    self?.completeStop(generation: gen)
                }
                return .ok
            }
        case .reset(let force):
            if !force {
                return .error(.confirmationRequired)
            }
            generation += 1
            state = .stopped
            step = nil
            lastError = nil
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: "reset"))
            return .ok
        case .status, .subscribe:
            return .ok
        }
    }

    private func completeStart(generation: UInt64) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .starting else {
                return
            }
            state = .running
            step = "fakeVM"
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: "fake VM running"))
        }
        broadcast(events)
    }

    private func completeStop(generation: UInt64) {
        var events: [EngineEvent] = []
        withLock {
            guard generation == self.generation, state == .stopping else {
                return
            }
            state = .stopped
            step = nil
            events.append(.status(currentStatusLocked()))
            events.append(.log(source: .engine, line: "stopped"))
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
