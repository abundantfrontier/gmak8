import Foundation
import ServiceManagement

public protocol LaunchAgentRegistering: Sendable {
    func register() throws
    func unregister() throws
}

public struct SMAppServiceAgent: LaunchAgentRegistering, Sendable {
    public init() {}

    public func register() throws {
        try SMAppServiceStatusGate.register(SMAppService.agent(plistName: CoreLaunchAgent.plistName))
    }

    public func unregister() throws {
        try SMAppServiceStatusGate.unregister(SMAppService.agent(plistName: CoreLaunchAgent.plistName))
    }
}

public enum CoreLaunchAgent {
    public static let label = "dev.gmak8.core"
    public static let plistName = "dev.gmak8.core.plist"
    public static let bundleProgram = "Contents/MacOS/gmak8-core"
    /// `KeepAlive.SuccessfulExit` in the LaunchAgent plist. `prepareUpdate` exits 0.
    public static let keepAliveSuccessfulExit = false

    public static func executableURL(bundleURL: URL) -> URL {
        bundleURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "MacOS", directoryHint: .isDirectory)
            .appending(path: "gmak8-core")
    }

    /// Settings copy for the two Login Items rows.
    public static let twoLoginItemsExplanation =
        "gmak8 uses two Login Items: (1) gmak8-core LaunchAgent, which owns the background cluster, "
        + "and (2) the gmak8 menu extra, which shows status at login. The agent is required for the "
        + "cluster to stay up; the extra is required if you enable launch at login."

    public static func register(
        bundleURL: URL,
        checker: any TranslocationChecking = TranslocationChecker(),
        service: any LaunchAgentRegistering = SMAppServiceAgent()
    ) throws {
        if checker.shouldRefuseRegister(bundleURL: bundleURL) {
            throw EngineErrorCode.translocated
        }
        try service.register()
    }

    public static func unregister(service: any LaunchAgentRegistering = SMAppServiceAgent()) throws {
        try service.unregister()
    }

    /// When `engine.sock` is dead, unregister first so a new register refreshes launchd LWCR.
    /// Ad-hoc Debug swaps can leave launchd in `EX_CONFIG`; then launch the bundled core directly.
    public static func ensureRegistered(
        bundleURL: URL,
        socketIsLive: Bool,
        checker: any TranslocationChecking = TranslocationChecker(),
        service: any LaunchAgentRegistering = SMAppServiceAgent()
    ) throws {
        if checker.shouldRefuseRegister(bundleURL: bundleURL) {
            throw EngineErrorCode.translocated
        }
        if !socketIsLive {
            try service.unregister()
        }
        try service.register()
    }

    public static func ensureRunning(
        bundleURL: URL,
        socketIsLive: Bool,
        checker: any TranslocationChecking = TranslocationChecker(),
        service: any LaunchAgentRegistering = SMAppServiceAgent(),
        isLive: () -> Bool,
        launch: (URL) throws -> Void
    ) throws {
        try ensureRegistered(
            bundleURL: bundleURL,
            socketIsLive: socketIsLive,
            checker: checker,
            service: service
        )
        if !isLive() {
            try launch(bundleURL)
        }
    }
}

public struct SMAppServiceMainApp: LaunchAgentRegistering, Sendable {
    public init() {}

    public func register() throws {
        try SMAppServiceStatusGate.register(SMAppService.mainApp)
    }

    public func unregister() throws {
        try SMAppServiceStatusGate.unregister(SMAppService.mainApp)
    }
}

private enum SMAppServiceStatusGate {
    static func register(_ service: SMAppService) throws {
        if service.status == .enabled {
            return
        }
        do {
            try service.register()
        } catch {
            if service.status == .enabled {
                return
            }
            throw error
        }
    }

    static func unregister(_ service: SMAppService) throws {
        if service.status == .notRegistered {
            return
        }
        do {
            try service.unregister()
        } catch {
            if service.status == .notRegistered {
                return
            }
            throw error
        }
    }
}

public enum LoginItemAction: Equatable, Sendable {
    case register
    case unregister
    case keep
}

public struct LoginItemMutation: Equatable, Sendable {
    public var extra: LoginItemAction
    public var agent: LoginItemAction

    public init(extra: LoginItemAction, agent: LoginItemAction) {
        self.extra = extra
        self.agent = agent
    }
}

public enum LaunchAtLoginPolicy {
    public static func mutation(enabling: Bool) -> LoginItemMutation {
        if enabling {
            return LoginItemMutation(extra: .register, agent: .register)
        }
        return LoginItemMutation(extra: .unregister, agent: .keep)
    }

    public static func extraDidLaunch() -> LoginItemMutation {
        LoginItemMutation(extra: .keep, agent: .register)
    }

    public static func apply(_ mutation: LoginItemMutation, bundleURL: URL) throws {
        switch mutation.extra {
        case .register:
            try ExtraLoginItem.register(bundleURL: bundleURL)
        case .unregister:
            try ExtraLoginItem.unregister()
        case .keep:
            break
        }
        switch mutation.agent {
        case .register:
            try CoreLaunchAgent.register(bundleURL: bundleURL)
        case .unregister:
            try CoreLaunchAgent.unregister()
        case .keep:
            break
        }
    }
}

public enum ExtraLoginItem {
    public static func register(
        bundleURL: URL,
        checker: any TranslocationChecking = TranslocationChecker(),
        service: any LaunchAgentRegistering = SMAppServiceMainApp()
    ) throws {
        if checker.shouldRefuseRegister(bundleURL: bundleURL) {
            throw EngineErrorCode.translocated
        }
        try service.register()
    }

    public static func unregister(service: any LaunchAgentRegistering = SMAppServiceMainApp()) throws {
        try service.unregister()
    }
}
