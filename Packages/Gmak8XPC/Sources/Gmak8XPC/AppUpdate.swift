import Darwin
import Foundation

public enum SparklePin {
    public static let feedURL = "https://github.com/gmak8/gmak8/releases/latest/download/appcast.xml"
    /// Ed25519 public key only. The matching private key is a GitHub Actions secret.
    public static let publicEDKey = "upvgFk63M1HEra9w5l3GAlBYFSm8NCcXpAPQhDPOTLk="
}

public enum AppUpdateCopy {
    public static let checkForUpdates = "Check for Updates…"
    public static let restartsCluster = "Updates restart the cluster."
    public static let coreStillRunning =
        "gmak8-core is still running. Do not replace gmak8.app while gmak8-core is alive."
}

public enum AppUpdateError: Error, Equatable, LocalizedError {
    case timeoutWaitingForCore

    public var errorDescription: String? {
        switch self {
        case .timeoutWaitingForCore:
            return AppUpdateCopy.coreStillRunning
        }
    }
}

public enum AppUpdatePrepareSubmit: Equatable, Sendable {
    case accepted
    case coreNotRunning
}

public enum AppUpdateFinishAction: Equatable, Sendable {
    case idle
    case startCluster
}

public enum AppUpdatePolicy {
    public static let waitTimeout: TimeInterval = 60
    /// How long to wait for `SMAppService.register()` / RunAtLoad to bring `engine.sock` up.
    public static let agentStartTimeout: TimeInterval = 5

    /// Unregister `gmak8-core` only. The menu extra login item stays.
    public static func duringSwap() -> LoginItemMutation {
        LoginItemMutation(extra: .keep, agent: .unregister)
    }

    public static func afterSwap() -> LoginItemMutation {
        LoginItemMutation(extra: .keep, agent: .register)
    }

    public static func shouldStartAfterSwap(keepClusterRunningOnQuit: Bool) -> Bool {
        keepClusterRunningOnQuit
    }
}

public struct AppUpdatePendingRelaunch: Equatable, Sendable {
    public var startCluster: Bool

    public init(startCluster: Bool) {
        self.startCluster = startCluster
    }
}

public enum AppUpdatePendingStart {
    public static let defaultsKey = "gmak8.pendingStartAfterUpdate"
    public static let postSwapKey = "gmak8.pendingPostSwap"

    public static func mark(keepClusterRunningOnQuit: Bool, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: postSwapKey)
        defaults.set(keepClusterRunningOnQuit, forKey: defaultsKey)
    }

    public static func consume(defaults: UserDefaults = .standard) -> AppUpdatePendingRelaunch? {
        guard defaults.bool(forKey: postSwapKey) else {
            return nil
        }
        let startCluster = defaults.bool(forKey: defaultsKey)
        clear(defaults: defaults)
        return AppUpdatePendingRelaunch(startCluster: startCluster)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: postSwapKey)
        defaults.removeObject(forKey: defaultsKey)
    }
}

public enum AppUpdateInstall {
    public static func waitForCoreExit(
        submitPrepareUpdate: () throws -> AppUpdatePrepareSubmit,
        wait: () -> Bool
    ) throws {
        _ = try submitPrepareUpdate()
        if !wait() {
            throw AppUpdateError.timeoutWaitingForCore
        }
    }

    /// Unregister only after sock+flocks are gone so launchd does not SIGTERM a still-stopping core.
    public static func prepareWillInstall(
        submitPrepareUpdate: () throws -> AppUpdatePrepareSubmit,
        wait: () -> Bool,
        unregisterAgent: () throws -> Void
    ) throws {
        try waitForCoreExit(submitPrepareUpdate: submitPrepareUpdate, wait: wait)
        try unregisterAgent()
    }

    public static func finishAfterSwap(
        bundleURL: URL,
        keepClusterRunningOnQuit: Bool,
        registerAgent: (URL) throws -> Void,
        waitUntilLive: () -> Bool,
        launchCore: (URL) throws -> Void
    ) throws -> AppUpdateFinishAction {
        try registerAgent(bundleURL)
        if !waitUntilLive() {
            try launchCore(bundleURL)
        }
        if AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: keepClusterRunningOnQuit) {
            return .startCluster
        }
        return .idle
    }

    public static func restoreCoreAfterFailedPrepare(
        bundleURL: URL,
        unregisterAgent: () throws -> Void,
        registerAgent: (URL) throws -> Void,
        waitUntilLive: () -> Bool,
        launchCore: (URL) throws -> Void
    ) throws {
        try unregisterAgent()
        try registerAgent(bundleURL)
        if waitUntilLive() {
            return
        }
        try launchCore(bundleURL)
    }
}

public enum EngineSocketProbe {
    /// True only if `connect(2)` succeeds. A leftover `engine.sock` inode is not live.
    public static func isLive(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        defer { Darwin.close(fd) }
        guard var addr = unixAddress(path: path) else {
            return false
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }
}

public enum AppUpdateGate {
    public static func waitUntilCoreReleased(
        socketURL: URL,
        lockURLs: [URL],
        timeout: TimeInterval = AppUpdatePolicy.waitTimeout,
        pollInterval: TimeInterval = 0.05,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        socketLive: (URL) -> Bool = EngineSocketProbe.isLive,
        locksHeld: ([URL]) -> Bool = DiskLockProbe.anyHeld
    ) -> Bool {
        let deadline = now().addingTimeInterval(timeout)
        while true {
            if !socketLive(socketURL) && !locksHeld(lockURLs) {
                return true
            }
            if now() >= deadline {
                return false
            }
            sleep(pollInterval)
        }
    }

    public static func waitUntilCoreLive(
        socketURL: URL,
        timeout: TimeInterval = AppUpdatePolicy.agentStartTimeout,
        pollInterval: TimeInterval = 0.05,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        socketLive: (URL) -> Bool = EngineSocketProbe.isLive
    ) -> Bool {
        let deadline = now().addingTimeInterval(timeout)
        while true {
            if socketLive(socketURL) {
                return true
            }
            if now() >= deadline {
                return false
            }
            sleep(pollInterval)
        }
    }
}

public enum DiskLockProbe {
    public static func anyHeld(urls: [URL]) -> Bool {
        for url in urls {
            if isHeld(url: url) {
                return true
            }
        }
        return false
    }

    public static func isHeld(url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let fd = open(path, O_RDWR)
        if fd < 0 {
            return errno != ENOENT
        }
        defer { Darwin.close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            return errno == EWOULDBLOCK || errno == EAGAIN
        }
        _ = flock(fd, LOCK_UN)
        return false
    }
}

private func unixAddress(path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
    let pathBytes = path.utf8.count
    guard pathBytes + 1 <= maxPath else {
        return nil
    }
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        path.withCString { cString in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: pathBytes + 1))
        }
    }
    return addr
}

public enum BundledCoreLauncher {
    public static func executableURL(bundleURL: URL) -> URL {
        CoreLaunchAgent.executableURL(bundleURL: bundleURL)
    }

    public static func launch(bundleURL: URL) throws {
        let url = executableURL(bundleURL: bundleURL)
        let process = Process()
        process.executableURL = url
        process.arguments = []
        try process.run()
    }
}
