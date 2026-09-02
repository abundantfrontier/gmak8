import Darwin
import Foundation
import Gmak8Kit
import Testing

@testable import Gmak8XPC

struct AppUpdateTests {
    @Test func swapUnregistersCoreAgentOnly() {
        let mutation = AppUpdatePolicy.duringSwap()
        #expect(mutation.extra == .keep)
        #expect(mutation.agent == .unregister)
        #expect(!CoreLaunchAgent.keepAliveSuccessfulExit)
    }

    @Test func afterSwapRegistersCoreAgentOnly() {
        let mutation = AppUpdatePolicy.afterSwap()
        #expect(mutation.extra == .keep)
        #expect(mutation.agent == .register)
        #expect(
            CoreLaunchAgent.executableURL(bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"))
                .path(percentEncoded: false) == "/Applications/gmak8.app/Contents/MacOS/gmak8-core"
        )
    }

    @Test func optionalStartHonorsKeepClusterRunningOnQuit() {
        #expect(AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: true))
        #expect(!AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: false))
        #expect(AppUpdateCopy.restartsCluster == "Updates restart the cluster.")
        #expect(AppUpdateCopy.checkForUpdates == "Check for Updates…")
    }

    @Test func pendingStartConsumeMatchesMarkedKeepRunning() {
        let suite = "gmak8.update-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        AppUpdatePendingStart.mark(keepClusterRunningOnQuit: true, defaults: defaults)
        #expect(AppUpdatePendingStart.consume(defaults: defaults)?.startCluster == true)
        #expect(AppUpdatePendingStart.consume(defaults: defaults) == nil)
        AppUpdatePendingStart.mark(keepClusterRunningOnQuit: false, defaults: defaults)
        #expect(AppUpdatePendingStart.consume(defaults: defaults)?.startCluster == false)
        AppUpdatePendingStart.mark(keepClusterRunningOnQuit: true, defaults: defaults)
        AppUpdatePendingStart.clear(defaults: defaults)
        #expect(AppUpdatePendingStart.consume(defaults: defaults) == nil)
    }

    @Test func prepareUnregistersAgentAfterWait() throws {
        let agent = MockUpdateLaunchAgent()
        var submitted = false
        try AppUpdateInstall.prepareWillInstall(
            submitPrepareUpdate: {
                submitted = true
                return .accepted
            },
            wait: { true },
            unregisterAgent: { try agent.unregister() }
        )
        #expect(submitted)
        #expect(agent.unregisterCount == 1)
        #expect(agent.registerCount == 0)
    }

    @Test func prepareDoesNotUnregisterWhenWaitTimesOut() {
        let agent = MockUpdateLaunchAgent()
        #expect(throws: AppUpdateError.timeoutWaitingForCore) {
            try AppUpdateInstall.prepareWillInstall(
                submitPrepareUpdate: { .accepted },
                wait: { false },
                unregisterAgent: { try agent.unregister() }
            )
        }
        #expect(agent.unregisterCount == 0)
    }

    @Test func prepareTreatsMissingCoreAsAlreadyGone() throws {
        try AppUpdateInstall.prepareWillInstall(
            submitPrepareUpdate: { .coreNotRunning },
            wait: { true },
            unregisterAgent: {}
        )
    }

    @Test func waitSucceedsWhenSocketGoneAndLocksFree() {
        let clock = FakeClock()
        let released = AppUpdateGate.waitUntilCoreReleased(
            socketURL: URL(fileURLWithPath: "/tmp/missing.engine.sock"),
            lockURLs: [],
            timeout: AppUpdatePolicy.waitTimeout,
            pollInterval: 0.05,
            now: { clock.now },
            sleep: { clock.sleep($0) },
            socketLive: { _ in false },
            locksHeld: { _ in false }
        )
        #expect(released)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func waitTimeoutFailsUpdateWhenSocketStays() {
        let clock = FakeClock()
        let released = AppUpdateGate.waitUntilCoreReleased(
            socketURL: URL(fileURLWithPath: "/tmp/live.engine.sock"),
            lockURLs: [URL(fileURLWithPath: "/tmp/os.img.lock")],
            timeout: AppUpdatePolicy.waitTimeout,
            pollInterval: 1,
            now: { clock.now },
            sleep: { clock.sleep($0) },
            socketLive: { _ in true },
            locksHeld: { _ in false }
        )
        #expect(!released)
        #expect(clock.now >= Date(timeIntervalSince1970: AppUpdatePolicy.waitTimeout))
    }

    @Test func waitTimeoutFailsWhenFlockHeld() {
        let clock = FakeClock()
        let released = AppUpdateGate.waitUntilCoreReleased(
            socketURL: URL(fileURLWithPath: "/tmp/missing.engine.sock"),
            lockURLs: [URL(fileURLWithPath: "/tmp/data.img.lock")],
            timeout: AppUpdatePolicy.waitTimeout,
            pollInterval: 1,
            now: { clock.now },
            sleep: { clock.sleep($0) },
            socketLive: { _ in false },
            locksHeld: { _ in true }
        )
        #expect(!released)
    }

    @Test func waitRequiresBothSocketAndFlock() {
        let clock = FakeClock()
        var socketLive = true
        var locksHeld = true
        var polls = 0
        let released = AppUpdateGate.waitUntilCoreReleased(
            socketURL: URL(fileURLWithPath: "/tmp/engine.sock"),
            lockURLs: [URL(fileURLWithPath: "/tmp/os.img.lock")],
            timeout: AppUpdatePolicy.waitTimeout,
            pollInterval: 1,
            now: { clock.now },
            sleep: { interval in
                polls += 1
                if polls == 1 {
                    socketLive = false
                }
                if polls == 2 {
                    locksHeld = false
                }
                clock.sleep(interval)
            },
            socketLive: { _ in socketLive },
            locksHeld: { _ in locksHeld }
        )
        #expect(released)
        #expect(polls == 2)
    }

    @Test func diskLockProbeSeesHeldSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-update-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appending(path: "os.img.lock")
        let path = lockURL.path(percentEncoded: false)
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        #expect(fd >= 0)
        defer { Darwin.close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        #expect(DiskLockProbe.isHeld(url: lockURL))
        #expect(flock(fd, LOCK_UN) == 0)
        #expect(!DiskLockProbe.isHeld(url: lockURL))
        #expect(!DiskLockProbe.isHeld(url: root.appending(path: "missing.lock")))
    }

    @Test func finishAfterSwapRegistersAndStartsWhenKeepRunning() throws {
        let agent = MockUpdateLaunchAgent()
        var launched: URL?
        let action = try AppUpdateInstall.finishAfterSwap(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            keepClusterRunningOnQuit: true,
            registerAgent: { url in
                try CoreLaunchAgent.register(bundleURL: url, service: agent)
            },
            waitUntilLive: { false },
            launchCore: { url in
                launched = BundledCoreLauncher.executableURL(bundleURL: url)
            }
        )
        #expect(agent.registerCount == 1)
        #expect(agent.unregisterCount == 0)
        #expect(launched?.lastPathComponent == "gmak8-core")
        #expect(action == .startCluster)
    }

    @Test func finishAfterSwapDoesNotLaunchWhenAgentAlreadyLive() throws {
        var launched = false
        let action = try AppUpdateInstall.finishAfterSwap(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            keepClusterRunningOnQuit: false,
            registerAgent: { _ in },
            waitUntilLive: { true },
            launchCore: { _ in launched = true }
        )
        #expect(!launched)
        #expect(action == .idle)
    }

    @Test func finishAfterSwapSkipsStartWhenKeepRunningOff() throws {
        let action = try AppUpdateInstall.finishAfterSwap(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            keepClusterRunningOnQuit: false,
            registerAgent: { _ in },
            waitUntilLive: { false },
            launchCore: { _ in }
        )
        #expect(action == .idle)
    }

    @Test func finishAfterSwapRefusesTranslocatedBundle() {
        let agent = MockUpdateLaunchAgent()
        #expect(throws: EngineErrorCode.translocated) {
            try AppUpdateInstall.finishAfterSwap(
                bundleURL: URL(fileURLWithPath: "/Users/tester/Downloads/gmak8.app"),
                keepClusterRunningOnQuit: true,
                registerAgent: { url in
                    try CoreLaunchAgent.register(bundleURL: url, service: agent)
                },
                waitUntilLive: { false },
                launchCore: { _ in }
            )
        }
        #expect(agent.registerCount == 0)
    }

    @Test func leftoverSocketFileIsNotLive() throws {
        let sock = URL(fileURLWithPath: "/tmp/gmak8-stale-\(UUID().uuidString.prefix(8)).sock")
        try Data("stale".utf8).write(to: sock)
        defer { try? FileManager.default.removeItem(at: sock) }
        #expect(!EngineSocketProbe.isLive(sock))
        let clock = FakeClock()
        let released = AppUpdateGate.waitUntilCoreReleased(
            socketURL: sock,
            lockURLs: [],
            timeout: AppUpdatePolicy.waitTimeout,
            pollInterval: 1,
            now: { clock.now },
            sleep: { clock.sleep($0) },
            socketLive: EngineSocketProbe.isLive,
            locksHeld: { _ in false }
        )
        #expect(released)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func liveUnixSocketIsDetectedByConnect() throws {
        let sock = URL(fileURLWithPath: "/tmp/gmak8-live-\(UUID().uuidString.prefix(8)).sock")
        let listener = try listenUnix(sock)
        defer { listener.close() }
        #expect(EngineSocketProbe.isLive(sock))
        listener.close()
        #expect(!EngineSocketProbe.isLive(sock))
    }

    @Test func restoreReregistersAndLaunchesIfStillDead() throws {
        let agent = MockUpdateLaunchAgent()
        var launched = false
        try AppUpdateInstall.restoreCoreAfterFailedPrepare(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            unregisterAgent: { try agent.unregister() },
            registerAgent: { url in
                try CoreLaunchAgent.register(bundleURL: url, service: agent)
            },
            waitUntilLive: { false },
            launchCore: { _ in launched = true }
        )
        #expect(agent.unregisterCount == 1)
        #expect(agent.registerCount == 1)
        #expect(launched)
    }

    @Test func restoreDoesNotLaunchWhenRegisterBringsCoreBack() throws {
        var launched = false
        try AppUpdateInstall.restoreCoreAfterFailedPrepare(
            bundleURL: URL(fileURLWithPath: "/Applications/gmak8.app"),
            unregisterAgent: {},
            registerAgent: { _ in },
            waitUntilLive: { true },
            launchCore: { _ in launched = true }
        )
        #expect(!launched)
    }

    @Test func launchAgentPlistDoesNotKeepAliveSuccessfulExit() throws {
        let url = repositoryRoot().appending(path: "Apps/gmak8/Gmak8Core/dev.gmak8.core.plist")
        let data = try Data(contentsOf: url)
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let keepAlive = obj?["KeepAlive"] as? [String: Any]
        #expect(keepAlive?["SuccessfulExit"] as? Bool == false)
    }

    @Test func sparklePublicKeyIsNotPrivateMaterial() throws {
        #expect(SparklePin.feedURL.hasPrefix("https://"))
        #expect(!SparklePin.publicEDKey.contains("PRIVATE"))
        #expect(Data(base64Encoded: SparklePin.publicEDKey)?.count == 32)
        let plistURL = repositoryRoot().appending(path: "Apps/gmak8/App/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(obj?["SUFeedURL"] as? String == SparklePin.feedURL)
        #expect(obj?["SUPublicEDKey"] as? String == SparklePin.publicEDKey)
        #expect(obj?["SUAutomaticallyUpdate"] as? Bool == false)
    }

    @Test func repositoryHasNoPrivateSigningKeys() throws {
        let root = repositoryRoot()
        var forbidden: [String] = []
        let skip = Set([".git", ".build", "DerivedData", "xcuserdata"])
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let item = enumerator?.nextObject() as? URL {
            if skip.contains(item.lastPathComponent) {
                enumerator?.skipDescendants()
                continue
            }
            let name = item.lastPathComponent
            let lower = name.lowercased()
            if lower == "cosign.key" || lower.hasSuffix(".p8") || lower.contains("eddsa_private")
                || lower.contains("sparkle_private") || lower.contains("notary-key")
            {
                forbidden.append(item.path(percentEncoded: false))
                continue
            }
            guard lower.hasSuffix(".pem") || lower.hasSuffix(".key") else {
                continue
            }
            if let body = try? String(contentsOf: item, encoding: .utf8),
                body.contains("PRIVATE KEY")
            {
                forbidden.append(item.path(percentEncoded: false))
            }
        }
        #expect(forbidden.isEmpty)
    }
}

private func listenUnix(_ url: URL) throws -> UnixListener {
    try UnixListener(url: url)
}

private final class UnixListener: @unchecked Sendable {
    private var fd: Int32
    private let path: String

    init(url: URL) throws {
        path = url.path(percentEncoded: false)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw EngineErrorCode.invalidRequest
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let pathBytes = path.utf8.count
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes + 1 <= maxPath else {
            Darwin.close(fd)
            throw EngineErrorCode.invalidRequest
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            path.withCString { cString in
                buffer.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: pathBytes + 1))
            }
        }
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw EngineErrorCode.invalidRequest
        }
    }

    func close() {
        guard fd >= 0 else {
            return
        }
        Darwin.close(fd)
        fd = -1
        unlink(path)
    }
}

private func repositoryRoot(from filePath: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: filePath)
    for _ in 0..<12 {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(
            atPath: url.appending(path: "scripts/ci.sh").path(percentEncoded: false)
        ) {
            return url
        }
    }
    return url
}

private final class MockUpdateLaunchAgent: LaunchAgentRegistering, @unchecked Sendable {
    var registerCount = 0
    var unregisterCount = 0

    func register() throws {
        registerCount += 1
    }

    func unregister() throws {
        unregisterCount += 1
    }
}

private final class FakeClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 0)
    var sleeps: [TimeInterval] = []

    func sleep(_ interval: TimeInterval) {
        sleeps.append(interval)
        now = now.addingTimeInterval(interval)
    }
}
