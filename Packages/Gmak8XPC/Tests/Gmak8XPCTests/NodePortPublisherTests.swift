import Foundation
import Gmak8GuestClient
import Testing

@testable import Gmak8XPC

struct NodePortPublisherTests {
    @Test func publishesNodePortAndLoadBalancerSkipsClusterIPAndUDP() async throws {
        let source = FakeServiceSource(services: [
            GuestService(
                namespace: "default",
                name: "kubernetes",
                type: "ClusterIP",
                ports: [GuestServicePort(port: 443, nodePort: nil, protocolName: "TCP")]
            ),
            GuestService(
                namespace: "default",
                name: "nginx",
                type: "NodePort",
                ports: [GuestServicePort(name: "http", port: 80, nodePort: 30080, protocolName: "TCP")]
            ),
            GuestService(
                namespace: "kube-system",
                name: "traefik",
                type: "LoadBalancer",
                ports: [
                    GuestServicePort(name: "web", port: 80, nodePort: 30779, protocolName: "TCP"),
                    GuestServicePort(name: "websecure", port: 443, nodePort: 31204, protocolName: "TCP"),
                ]
            ),
            GuestService(
                namespace: "kube-system",
                name: "dns",
                type: "NodePort",
                ports: [GuestServicePort(port: 53, nodePort: 30053, protocolName: "UDP")]
            ),
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }

        try await waitUntil {
            publisher.snapshot().count == 3
        }
        let ports = publisher.snapshot()
        #expect(ports.map(\.service) == ["nginx", "traefik", "traefik"])
        #expect(Set(exposer.boundKeys) == [30080, 30779, 31204])
        #expect(exposer.bound[30080] == 30080)
        #expect(ports[0].hostURL == "http://127.0.0.1:30080")
        #expect(ports[1].collision == .published)
        #expect(ports[2].hostURL == "https://127.0.0.1:31204")
        #expect(!exposer.boundKeys.contains(30053))
    }

    @Test func addressAlreadyInUseIsCollisionNotPublished() async throws {
        let source = FakeServiceSource(services: [
            nodePort("busy", nodePort: 30080)
        ])
        let exposer = FakeExposer()
        exposer.collisions = [30080]
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }

        try await waitUntil {
            publisher.snapshot().first?.collision == .collision
        }
        #expect(exposer.bound[30080] == nil)
        #expect(publisher.snapshot()[0].hostPort == 30080)
        #expect(publisher.snapshot()[0].collision == .collision)
    }

    @Test func forbiddenHostPortsAreNotBound() async throws {
        let source = FakeServiceSource(services: [
            nodePort("ssh", port: 22, nodePort: 22),
            nodePort("http", port: 80, nodePort: 80),
            nodePort("https", port: 443, nodePort: 443),
            nodePort("ok", nodePort: 30080),
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }

        try await waitUntil {
            publisher.snapshot().count == 4
        }
        let byName = Dictionary(uniqueKeysWithValues: publisher.snapshot().map { ($0.service, $0) })
        #expect(byName["ssh"]?.collision == .forbidden)
        #expect(byName["http"]?.collision == .forbidden)
        #expect(byName["https"]?.collision == .forbidden)
        #expect(byName["ok"]?.collision == .published)
        #expect(exposer.boundKeys == Set([30080]))
        #expect(!exposer.exposeCalls.contains { NodePortPublisher.forbiddenHostPorts.contains($0.0) })
    }

    @Test func reservedBaselineHostPortIsCollision() async throws {
        let source = FakeServiceSource(services: [
            nodePort("clash", nodePort: 8080)
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source,
            exposer: exposer,
            baseline: {
                [
                    PublishedPort.loopback(
                        service: "http",
                        port: 80,
                        nodePort: 80,
                        hostPort: 8080,
                        guestPort: 80,
                        scheme: "http",
                        preferredHostPort: 8080
                    )
                ]
            },
            pollInterval: .milliseconds(5)
        )
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }

        try await waitUntil {
            publisher.snapshot().contains { $0.service == "clash" && $0.collision == .collision }
        }
        #expect(exposer.bound[8080] == nil)
        #expect(publisher.snapshot().contains { $0.service == "http" && $0.hostPort == 8080 })
    }

    @Test func capWarnsAt32AndDoesNotBindMore() async throws {
        var services: [GuestService] = []
        for index in 0..<33 {
            services.append(nodePort("svc-\(String(format: "%02d", index))", nodePort: 30000 + index))
        }
        let source = FakeServiceSource(services: services)
        let exposer = FakeExposer()
        let logBox = LogBox()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(
            onChange: {},
            log: { line in
                logBox.append(line)
            }
        )
        defer { publisher.cancel() }

        try await waitUntil {
            publisher.snapshot().filter { $0.collision == .capped }.count == 1
        }
        #expect(exposer.boundKeys.count == 32)
        #expect(publisher.snapshot().filter { $0.collision == .published }.count == 32)
        #expect(publisher.snapshot().contains { $0.collision == .capped && $0.nodePort == 30032 })
        #expect(logBox.lines.contains { $0.contains("32") })
    }

    @Test func cancelUnexposesAndDropsTable() async throws {
        let source = FakeServiceSource(services: [
            nodePort("nginx", nodePort: 30080)
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        try await waitUntil { exposer.bound[30080] == 30080 }
        publisher.cancel()
        #expect(publisher.snapshot().isEmpty)
        #expect(exposer.unexposeCalls.contains(30080))
        #expect(exposer.bound[30080] == nil)
    }

    @Test func disabledDropsNodePortsKeepsBaseline() async throws {
        let enabled = Flag(true)
        let source = FakeServiceSource(services: [
            nodePort("nginx", nodePort: 30080)
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source,
            exposer: exposer,
            isEnabled: { enabled.value },
            baseline: {
                [
                    PublishedPort.loopback(
                        service: "kubernetes",
                        port: 6443,
                        nodePort: 6443,
                        hostPort: 6443,
                        guestPort: 6443,
                        scheme: "https",
                        preferredHostPort: 6443
                    )
                ]
            },
            pollInterval: .milliseconds(5)
        )
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }
        try await waitUntil { exposer.bound[30080] == 30080 }
        enabled.value = false
        try await waitUntil {
            publisher.snapshot().count == 1 && publisher.snapshot()[0].service == "kubernetes"
        }
        #expect(exposer.unexposeCalls.contains(30080))
        #expect(exposer.bound[30080] == nil)
    }

    @Test func listFailureKeepsExistingBinds() async throws {
        let source = FakeServiceSource(services: [
            nodePort("nginx", nodePort: 30080)
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }
        try await waitUntil { exposer.bound[30080] == 30080 }
        source.setError(GuestAgentError.httpStatus(500, "kubectl failed"))
        try await Task.sleep(for: .milliseconds(80))
        #expect(exposer.bound[30080] == 30080)
        #expect(!exposer.unexposeCalls.contains(30080))
    }

    @Test func reexposeRebindsOwnedWhenListFails() async throws {
        let source = FakeServiceSource(services: [
            nodePort("nginx", nodePort: 30080)
        ])
        let exposer = FakeExposer()
        let publisher = NodePortPublisher(
            source: source, exposer: exposer, pollInterval: .milliseconds(5))
        publisher.start(onChange: {}, log: { _ in })
        defer { publisher.cancel() }
        try await waitUntil { exposer.bound[30080] == 30080 }
        source.setError(GuestAgentError.httpStatus(500, "kubectl failed"))
        try await Task.sleep(for: .milliseconds(20))
        exposer.dropBinds()
        #expect(exposer.bound[30080] == nil)
        publisher.reexpose()
        try await waitUntil { exposer.bound[30080] == 30080 }
        #expect(!exposer.unexposeCalls.contains(30080))
    }

    @Test func fakeEnginePathLeavesPublishedPortsEmpty() {
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        #expect(engine.currentStatus().state == .running)
        #expect(engine.currentStatus().publishedPorts.isEmpty)
    }

    @Test func injectedPublisherFillsEngineStatusThenDropsOnStop() {
        let scheduler = ManualEngineScheduler()
        let publisher = StubPortPublisher()
        publisher.ports = [
            PublishedPort(service: "nginx", hostPort: 30080, guestPort: 30080)
        ]
        let engine = ClusterEngine(scheduler: scheduler, publisher: publisher)
        #expect(engine.submit(.start) == .ok)
        #expect(engine.currentStatus().publishedPorts.isEmpty)
        scheduler.runNext()
        #expect(publisher.started)
        #expect(engine.currentStatus().publishedPorts.map(\.hostPort) == [30080])
        #expect(engine.submit(.stop) == .ok)
        scheduler.runNext()
        #expect(publisher.cancelled)
        #expect(engine.currentStatus().publishedPorts.isEmpty)
    }

    @Test func gvproxyRestartReexposesTable() {
        let scheduler = ManualEngineScheduler()
        let runtime = StubRuntime()
        let publisher = StubPortPublisher()
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime, publisher: publisher)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        runtime.fireDegraded("gvproxy restarted; guest overlay datapath may be dead")
        #expect(engine.currentStatus().state == .degraded)
        #expect(publisher.reexposeCount == 1)
    }
}

private func nodePort(
    _ name: String,
    namespace: String = "default",
    port: Int = 80,
    nodePort: Int,
    type: String = "NodePort",
    proto: String = "TCP"
) -> GuestService {
    GuestService(
        namespace: namespace,
        name: name,
        type: type,
        ports: [GuestServicePort(name: nil, port: port, nodePort: nodePort, protocolName: proto)]
    )
}

private final class FakeServiceSource: GuestServiceSource, @unchecked Sendable {
    private let lock = NSLock()
    private var services: [GuestService]
    var error: (any Error)?

    init(services: [GuestService]) {
        self.services = services
    }

    func listServices() async throws -> [GuestService] {
        try current()
    }

    func setError(_ error: (any Error)?) {
        lock.lock()
        self.error = error
        lock.unlock()
    }

    private func current() throws -> [GuestService] {
        lock.lock()
        defer { lock.unlock() }
        if let error {
            throw error
        }
        return services
    }
}

private final class FakeExposer: HostPortExposer, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: Int] = [:]
    var collisions: Set<Int> = []
    private var exposes: [(Int, Int)] = []
    private var unexposes: [Int] = []

    var bound: [Int: Int] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var boundKeys: Set<Int> {
        Set(bound.keys)
    }

    var exposeCalls: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return exposes
    }

    var unexposeCalls: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return unexposes
    }

    func expose(hostPort: Int, guestPort: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        exposes.append((hostPort, guestPort))
        if collisions.contains(hostPort) {
            throw HostPortExposeError.addressInUse(hostPort)
        }
        if let current = storage[hostPort], current != guestPort {
            throw HostPortExposeError.addressInUse(hostPort)
        }
        storage[hostPort] = guestPort
    }

    func unexpose(hostPort: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        unexposes.append(hostPort)
        storage[hostPort] = nil
    }

    func dropBinds() {
        lock.lock()
        storage = [:]
        lock.unlock()
    }
}

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Bool
    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
    init(_ value: Bool) {
        storage = value
    }
}

private final class StubPortPublisher: PortPublisher, @unchecked Sendable {
    private let lock = NSLock()
    var ports: [PublishedPort] = []
    var started = false
    var cancelled = false
    var reexposeCount = 0
    private var onChange: (@Sendable () -> Void)?

    func snapshot() -> [PublishedPort] {
        lock.lock()
        defer { lock.unlock() }
        guard started, !cancelled else {
            return []
        }
        return ports
    }

    func start(onChange: @escaping @Sendable () -> Void, log: @escaping @Sendable (String) -> Void) {
        lock.lock()
        started = true
        cancelled = false
        self.onChange = onChange
        lock.unlock()
        onChange()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        ports = []
        let notify = onChange
        onChange = nil
        lock.unlock()
        notify?()
    }

    func reexpose() {
        lock.lock()
        reexposeCount += 1
        lock.unlock()
    }
}

private final class StubRuntime: VirtualMachineRuntime, @unchecked Sendable {
    var stepName: String { "vm" }
    private var degradedHandler: (@Sendable (String) -> Void)?

    func preflight() -> VirtualMachinePreflightError? { nil }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }

    func setDegradedHandler(_ handler: (@Sendable (String) -> Void)?) {
        degradedHandler = handler
    }

    func fireDegraded(_ message: String) {
        degradedHandler?(message)
    }
}

private func waitUntil(timeout: Duration = .seconds(5), _ predicate: @escaping () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting for condition")
}
