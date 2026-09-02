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

public enum AppUpdatePendingStart {
    public static let defaultsKey = "gmak8.pendingStartAfterUpdate"

    public static func mark(keepClusterRunningOnQuit: Bool, defaults: UserDefaults = .standard) {
        defaults.set(keepClusterRunningOnQuit, forKey: defaultsKey)
    }

    public static func consume(defaults: UserDefaults = .standard) -> Bool {
        let value = defaults.bool(forKey: defaultsKey)
        defaults.removeObject(forKey: defaultsKey)
        return value
    }
}

public enum AppUpdateInstall {
    /// Send `prepareUpdate`, wait until the core process is gone, then unregister the agent.
    public static func prepareWillInstall(
        submitPrepareUpdate: () throws -> AppUpdatePrepareSubmit,
        wait: () -> Bool,
        unregisterAgent: () throws -> Void
    ) throws {
        _ = try submitPrepareUpdate()
        if !wait() {
            throw AppUpdateError.timeoutWaitingForCore
        }
        try unregisterAgent()
    }

    public static func finishAfterSwap(
        bundleURL: URL,
        keepClusterRunningOnQuit: Bool,
        registerAgent: (URL) throws -> Void,
        launchCore: (URL) throws -> Void
    ) throws -> AppUpdateFinishAction {
        try registerAgent(bundleURL)
        try launchCore(bundleURL)
        if AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: keepClusterRunningOnQuit) {
            return .startCluster
        }
        return .idle
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
        socketExists: (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        },
        locksHeld: ([URL]) -> Bool = DiskLockProbe.anyHeld
    ) -> Bool {
        let deadline = now().addingTimeInterval(timeout)
        while true {
            if !socketExists(socketURL) && !locksHeld(lockURLs) {
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
