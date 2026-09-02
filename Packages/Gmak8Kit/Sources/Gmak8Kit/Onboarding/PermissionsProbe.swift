import Foundation

public enum PermissionsOutcome: Equatable, Sendable {
    case unsupportedVirtualization
    case translocated
    case ready(nestedVirtualizationSupported: Bool)

    public var canContinue: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

public enum PermissionsProbe {
    public static func evaluate(
        virtualizationSupported: Bool,
        nestedVirtualizationSupported: Bool,
        shouldRefuseLaunchAgent: Bool
    ) -> PermissionsOutcome {
        if !virtualizationSupported {
            return .unsupportedVirtualization
        }
        if shouldRefuseLaunchAgent {
            return .translocated
        }
        return .ready(nestedVirtualizationSupported: nestedVirtualizationSupported)
    }

    public static func message(_ outcome: PermissionsOutcome) -> String {
        switch outcome {
        case .unsupportedVirtualization:
            return OnboardingCopy.unsupportedVirtualization
        case .translocated:
            return OnboardingCopy.moveToApplications
        case .ready(true):
            return OnboardingCopy.nestedVirtAvailable
        case .ready(false):
            return OnboardingCopy.nestedVirtUnavailable
        }
    }
}

public enum NestedVirtualizationProbe {
    public static func isSupported(macOSMajor: Int, platformReportsSupported: Bool) -> Bool {
        macOSMajor >= 15 && platformReportsSupported
    }
}
