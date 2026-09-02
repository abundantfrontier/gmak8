import Foundation
import ServiceManagement

public protocol LaunchAgentRegistering: Sendable {
    func register() throws
    func unregister() throws
}

public struct SMAppServiceAgent: LaunchAgentRegistering, Sendable {
    public init() {}

    public func register() throws {
        try SMAppService.agent(plistName: CoreLaunchAgent.plistName).register()
    }

    public func unregister() throws {
        try SMAppService.agent(plistName: CoreLaunchAgent.plistName).unregister()
    }
}

public enum CoreLaunchAgent {
    public static let label = "dev.gmak8.core"
    public static let plistName = "dev.gmak8.core.plist"
    public static let bundleProgram = "Contents/MacOS/gmak8-core"

    /// Settings / onboarding copy. gmak8 registers two Login Items; this PR ships only the agent.
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
}
