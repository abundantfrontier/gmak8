import Foundation
import Gmak8GuestClient

public protocol HostPortExposer: Sendable {
    func expose(hostPort: Int, guestPort: Int) throws
    func unexpose(hostPort: Int) throws
}

public enum HostPortExposeError: Error, Equatable, LocalizedError, Sendable {
    case addressInUse(Int)
    case forbidden(Int)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .addressInUse(let port):
            return "127.0.0.1:\(port) is already in use"
        case .forbidden(let port):
            return "refuse host port \(port)"
        case .failed(let reason):
            return reason
        }
    }
}

public protocol GuestServiceSource: Sendable {
    func listServices() async throws -> [GuestService]
}

public struct AgentServiceSource: GuestServiceSource {
    private let makeClient: @Sendable () async throws -> GuestAgentClient

    public init(makeClient: @escaping @Sendable () async throws -> GuestAgentClient) {
        self.makeClient = makeClient
    }

    public func listServices() async throws -> [GuestService] {
        try await makeClient().services().items
    }
}

public protocol PortPublisher: Sendable {
    func snapshot() -> [PublishedPort]
    func start(onChange: @escaping @Sendable () -> Void, log: @escaping @Sendable (String) -> Void)
    func cancel()
    func reexpose()
}

public struct NoOpPortPublisher: PortPublisher {
    public init() {}

    public func snapshot() -> [PublishedPort] { [] }

    public func start(onChange: @escaping @Sendable () -> Void, log: @escaping @Sendable (String) -> Void) {}

    public func cancel() {}

    public func reexpose() {}
}

/// Polls guest Services and exposes NodePorts on 127.0.0.1. Must not run on `dev.gmak8.vm`.
public final class NodePortPublisher: PortPublisher, @unchecked Sendable {
    public static let warnCap = 32
    public static let forbiddenHostPorts: Set<Int> = [22, 80, 443]

    private let source: any GuestServiceSource
    private let exposer: any HostPortExposer
    private let isEnabled: @Sendable () -> Bool
    private let baseline: @Sendable () -> [PublishedPort]
    private let pollInterval: Duration

    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = true
    private var onChange: (@Sendable () -> Void)?
    private var log: (@Sendable (String) -> Void)?
    private var snapshotStorage: [PublishedPort] = []
    private var owned: [String: OwnedBinding] = [:]
    private var baselineOwned: [String: OwnedBinding] = [:]
    private var reexposeRequested = false

    private struct OwnedBinding {
        var hostPort: Int
        var guestPort: Int
    }

    public init(
        source: any GuestServiceSource,
        exposer: any HostPortExposer,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        baseline: @escaping @Sendable () -> [PublishedPort] = { [] },
        pollInterval: Duration = .seconds(2)
    ) {
        self.source = source
        self.exposer = exposer
        self.isEnabled = isEnabled
        self.baseline = baseline
        self.pollInterval = pollInterval
    }

    public func snapshot() -> [PublishedPort] {
        withLock { snapshotStorage }
    }

    public func start(onChange: @escaping @Sendable () -> Void, log: @escaping @Sendable (String) -> Void) {
        withLock {
            if task != nil {
                return
            }
            cancelled = false
            reexposeRequested = false
            self.onChange = onChange
            self.log = log
            task = Task { [weak self] in
                await self?.runLoop()
            }
        }
    }

    public func cancel() {
        let ports: [OwnedBinding] = withLock {
            cancelled = true
            reexposeRequested = false
            task?.cancel()
            task = nil
            onChange = nil
            log = nil
            let current = Array(owned.values) + Array(baselineOwned.values)
            owned = [:]
            baselineOwned = [:]
            snapshotStorage = []
            return current
        }
        for binding in ports {
            try? exposer.unexpose(hostPort: binding.hostPort)
        }
    }

    public func reexpose() {
        withLock {
            if cancelled || task == nil {
                return
            }
            reexposeRequested = true
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let reexposeOwned = withLock {
                let value = reexposeRequested
                reexposeRequested = false
                return value
            }
            await reconcile(reexposeOwnedOnFailure: reexposeOwned)
            if withLock({ cancelled }) {
                return
            }
            if withLock({ reexposeRequested }) {
                continue
            }
            await sleepInterruptible()
        }
    }

    private func sleepInterruptible() async {
        let deadline = ContinuousClock.now + pollInterval
        while ContinuousClock.now < deadline {
            if withLock({ reexposeRequested || cancelled }) {
                return
            }
            let remaining = deadline - ContinuousClock.now
            let step: Duration = remaining < .milliseconds(50) ? remaining : .milliseconds(50)
            if step <= .zero {
                return
            }
            do {
                try await Task.sleep(for: step)
            } catch {
                return
            }
        }
    }

    private func reconcile(reexposeOwnedOnFailure: Bool) async {
        if withLock({ cancelled }) {
            return
        }
        let enabled = isEnabled()
        let services: [GuestService]
        if enabled {
            do {
                services = try await source.listServices()
            } catch {
                if reexposeOwnedOnFailure {
                    reapplyOwned()
                }
                return
            }
        } else {
            services = []
        }
        if withLock({ cancelled }) {
            return
        }

        let defaults = baseline()
        let previousOwned = withLock { owned }
        let previousBaseline = withLock { baselineOwned }
        let (defaultRows, nextBaseline) = bindBaseline(defaults, previous: previousBaseline)
        let desired = enabled ? publishablePorts(from: services) : []
        var reserved = Set(defaults.map(\.hostPort))
        reserved.formUnion(Self.forbiddenHostPorts)

        var nextOwned: [String: OwnedBinding] = [:]
        var rows: [PublishedPort] = []
        var usedHostPorts = reserved
        var boundCount = 0
        var hitCap = false
        let desiredKeys = Set(desired.map(\.key))

        for key in previousOwned.keys where !desiredKeys.contains(key) {
            if let binding = previousOwned[key] {
                try? exposer.unexpose(hostPort: binding.hostPort)
            }
        }

        for item in desired {
            if withLock({ cancelled }) {
                rollback(nextOwned: nextOwned, previousOwned: previousOwned)
                rollbackBaseline(next: nextBaseline, previous: previousBaseline)
                return
            }
            if Self.forbiddenHostPorts.contains(item.nodePort) {
                rows.append(item.row(collision: .forbidden))
                continue
            }
            if let existing = previousOwned[item.key], existing.hostPort == item.nodePort {
                if applyExpose(hostPort: existing.hostPort, guestPort: existing.guestPort) {
                    nextOwned[item.key] = existing
                    usedHostPorts.insert(existing.hostPort)
                    boundCount += 1
                    rows.append(item.row(collision: .published))
                } else {
                    rows.append(item.row(collision: .collision))
                }
                continue
            }
            if boundCount >= Self.warnCap {
                rows.append(item.row(collision: .capped))
                hitCap = true
                continue
            }
            if usedHostPorts.contains(item.nodePort) {
                rows.append(item.row(collision: .collision))
                continue
            }
            if applyExpose(hostPort: item.nodePort, guestPort: item.nodePort) {
                nextOwned[item.key] = OwnedBinding(hostPort: item.nodePort, guestPort: item.nodePort)
                usedHostPorts.insert(item.nodePort)
                boundCount += 1
                rows.append(item.row(collision: .published))
            } else {
                rows.append(item.row(collision: .collision))
            }
        }

        if withLock({ cancelled }) {
            rollback(nextOwned: nextOwned, previousOwned: previousOwned)
            rollbackBaseline(next: nextBaseline, previous: previousBaseline)
            return
        }

        let snapshot = defaultRows + rows
        let callbacks: (changed: Bool, notify: (@Sendable () -> Void)?, logger: (@Sendable (String) -> Void)?) =
            withLock {
                if cancelled {
                    return (false, nil, nil)
                }
                owned = nextOwned
                baselineOwned = nextBaseline
                let changed = snapshotStorage != snapshot
                snapshotStorage = snapshot
                return (changed, onChange, log)
            }
        if callbacks.notify == nil, withLock({ cancelled }) {
            rollback(nextOwned: nextOwned, previousOwned: previousOwned)
            rollbackBaseline(next: nextBaseline, previous: previousBaseline)
            return
        }
        if hitCap {
            callbacks.logger?("published port cap \(Self.warnCap); additional NodePorts were not bound")
        }
        if callbacks.changed {
            callbacks.notify?()
        }
    }

    private func reapplyOwned() {
        let bindings = withLock { Array(owned.values) + Array(baselineOwned.values) }
        for binding in bindings {
            if withLock({ cancelled }) {
                return
            }
            _ = applyExpose(hostPort: binding.hostPort, guestPort: binding.guestPort)
        }
    }

    private func bindBaseline(
        _ defaults: [PublishedPort],
        previous: [String: OwnedBinding]
    ) -> ([PublishedPort], [String: OwnedBinding]) {
        var nextBaseline: [String: OwnedBinding] = [:]
        var rows: [PublishedPort] = []
        for port in defaults {
            var row = port
            if port.service == L1SSHBridge.service {
                let key = "baseline:\(port.service):\(port.hostPort)"
                if Self.forbiddenHostPorts.contains(port.hostPort) {
                    row.collision = .forbidden
                } else if applyExpose(hostPort: port.hostPort, guestPort: port.guestPort) {
                    nextBaseline[key] = OwnedBinding(hostPort: port.hostPort, guestPort: port.guestPort)
                    row.collision = .published
                } else {
                    row.collision = .collision
                }
            }
            rows.append(row)
        }
        for (key, binding) in previous where nextBaseline[key] == nil {
            try? exposer.unexpose(hostPort: binding.hostPort)
        }
        return (rows, nextBaseline)
    }

    private func rollbackBaseline(next: [String: OwnedBinding], previous: [String: OwnedBinding]) {
        for (key, binding) in next where previous[key] == nil {
            try? exposer.unexpose(hostPort: binding.hostPort)
        }
    }

    private func applyExpose(hostPort: Int, guestPort: Int) -> Bool {
        do {
            try exposer.expose(hostPort: hostPort, guestPort: guestPort)
            return true
        } catch {
            return false
        }
    }

    private func rollback(nextOwned: [String: OwnedBinding], previousOwned: [String: OwnedBinding]) {
        for (key, binding) in nextOwned where previousOwned[key] == nil {
            try? exposer.unexpose(hostPort: binding.hostPort)
        }
    }

    private func publishablePorts(from services: [GuestService]) -> [DesiredPort] {
        var result: [DesiredPort] = []
        for service in services {
            guard service.type == "NodePort" || service.type == "LoadBalancer" else {
                continue
            }
            for port in service.ports {
                guard let nodePort = port.nodePort, nodePort > 0 else {
                    continue
                }
                let proto = (port.protocolName ?? "TCP").uppercased()
                guard proto == "TCP" else {
                    continue
                }
                result.append(
                    DesiredPort(
                        namespace: service.namespace,
                        name: service.name,
                        port: port.port,
                        nodePort: nodePort
                    )
                )
            }
        }
        result.sort { lhs, rhs in
            if lhs.namespace != rhs.namespace {
                return lhs.namespace < rhs.namespace
            }
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.nodePort < rhs.nodePort
        }
        return result
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private struct DesiredPort {
    var namespace: String
    var name: String
    var port: Int
    var nodePort: Int

    var key: String { "\(namespace)/\(name)/\(nodePort)" }

    func row(collision: PublishedPortCollision) -> PublishedPort {
        let scheme = port == 443 ? "https" : "http"
        return PublishedPort(
            service: name,
            namespace: namespace,
            port: port,
            nodePort: nodePort,
            hostPort: nodePort,
            guestPort: nodePort,
            hostURL: "\(scheme)://127.0.0.1:\(nodePort)",
            collision: collision
        )
    }
}
