import Foundation

public enum OnboardingPage: Int, CaseIterable, Equatable, Sendable {
    case welcome
    case whatYouGet
    case assets
    case permissions
    case profile
    case cli
    case createCluster

    public var isLast: Bool {
        self == .createCluster
    }

    public func advanced() -> OnboardingPage {
        OnboardingPage(rawValue: rawValue + 1) ?? self
    }

    public func back() -> OnboardingPage {
        OnboardingPage(rawValue: rawValue - 1) ?? self
    }

    public var primaryTitle: String {
        isLast ? OnboardingCopy.createAndStart : OnboardingCopy.continueTitle
    }
}

public enum FirstRunGate {
    public static func shouldShowOnboarding(settingsFileExists: Bool) -> Bool {
        !settingsFileExists
    }

    public static func shouldPersistSettings(needsOnboarding: Bool) -> Bool {
        !needsOnboarding
    }

    public static func clusterActionsEnabled(needsOnboarding: Bool) -> Bool {
        !needsOnboarding
    }
}

public struct OnboardingDraft: Equatable, Sendable {
    public var clusterName: String
    public var profile: Profile
    public var cpu: Int
    public var memoryGiB: Int
    public var dataDiskGiB: Int
    public var setCurrentContextOnStart: Bool
    public var profileRefusal: ProfileRefusal?

    public init(host: HostSnapshot) {
        clusterName = "gmak8"
        profile = .kubernetes
        setCurrentContextOnStart = false
        profileRefusal = nil
        switch Profile.kubernetes.resourceDefaults(host: host) {
        case .accepted(let resources):
            cpu = resources.cpu
            memoryGiB = resources.memoryGiB
            dataDiskGiB = resources.dataDiskGiB
        case .refused:
            cpu = 4
            memoryGiB = 4
            dataDiskGiB = 60
        }
    }

    public var profileIsAccepted: Bool {
        profileRefusal == nil
    }

    public mutating func applyProfile(_ profile: Profile, host: HostSnapshot) {
        self.profile = profile
        switch profile.resourceDefaults(host: host) {
        case .accepted(let resources):
            cpu = resources.cpu
            memoryGiB = resources.memoryGiB
            dataDiskGiB = resources.dataDiskGiB
            profileRefusal = nil
        case .refused(let refusal):
            profileRefusal = refusal
        }
    }

    public func makeSettings(host: HostSnapshot) throws -> Settings {
        if let profileRefusal {
            throw profileRefusal
        }
        var settings = try Settings.makeDefault(profile: profile, host: host)
        settings.clusterName = clusterName.isEmpty ? "gmak8" : clusterName
        settings.setCurrentContextOnStart = setCurrentContextOnStart
        settings.cpu = cpu
        settings.memoryGiB = memoryGiB
        settings.dataDiskGiB = dataDiskGiB
        return settings
    }
}

public enum OnboardingAdvance {
    public static func canLeave(
        page: OnboardingPage,
        permissions: PermissionsOutcome,
        guestReady: Bool,
        airgapReady: Bool,
        profileAccepted: Bool,
        guestRequired: Bool = true,
        airgapRequired: Bool = true
    ) -> Bool {
        let guestOK = !guestRequired || guestReady
        let airgapOK = !airgapRequired || airgapReady
        switch page {
        case .welcome, .whatYouGet, .cli:
            return true
        case .assets:
            return guestOK && airgapOK
        case .permissions:
            return permissions.canContinue
        case .profile:
            return profileAccepted
        case .createCluster:
            return guestOK && airgapOK && permissions.canContinue && profileAccepted
        }
    }
}
