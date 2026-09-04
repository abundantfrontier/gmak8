import Foundation

public enum OnboardingAssetKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case guest
    case k3sAirgap
    case kubevirtAirgap

    public var title: String {
        switch self {
        case .guest:
            return "Guest disk"
        case .k3sAirgap:
            return "Kubernetes images"
        case .kubevirtAirgap:
            return "KubeVirt images"
        }
    }

    /// Named default the user picks; Download fetches this, not an arbitrary file.
    public var defaultSource: String {
        switch self {
        case .guest:
            return "From GitHub abundantfrontier/gmak8 · Debian appliance · Apple Silicon"
        case .k3sAirgap:
            return "From GitHub k3s-io · Kubernetes 1.33.3 · Apple Silicon"
        case .kubevirtAirgap:
            return "KubeVirt 1.6.2 + CDI · Eureka profile · Apple Silicon"
        }
    }

    public var fileName: String {
        switch self {
        case .guest:
            return GuestAssetPin.bundled.fileName
        case .k3sAirgap:
            return AirgapPin.bundled.fileName
        case .kubevirtAirgap:
            return KubeVirtAirgapPin.bundled.fileName
        }
    }

    public var sizeBudget: String {
        switch self {
        case .guest, .k3sAirgap:
            return OnboardingCopy.sizeBudget500MiB
        case .kubevirtAirgap:
            return "≤ 1.5 GiB"
        }
    }

    public var isRequired: Bool {
        switch self {
        case .guest, .k3sAirgap:
            return true
        case .kubevirtAirgap:
            return false
        }
    }
}

public enum OnboardingAssets {
    public static func visible(for profile: Profile) -> [OnboardingAssetKind] {
        if profile == .kubernetes {
            return [.guest, .k3sAirgap]
        }
        return [.guest, .k3sAirgap, .kubevirtAirgap]
    }

    public static func isRequiredToContinue(_ kind: OnboardingAssetKind) -> Bool {
        switch kind {
        case .guest:
            return !GuestAssetPin.bundled.signed.hasStubDigest
        case .k3sAirgap:
            return !AirgapPin.bundled.signed.hasStubDigest
        case .kubevirtAirgap:
            return false
        }
    }

    public static func remoteDownloadEnabled(_ kind: OnboardingAssetKind) -> Bool {
        switch kind {
        case .guest:
            return GuestAssetPin.bundled.signed.remoteDownloadEnabled
        case .k3sAirgap:
            return AirgapPin.bundled.signed.remoteDownloadEnabled
        case .kubevirtAirgap:
            return KubeVirtAirgapPin.bundled.signed.remoteDownloadEnabled
        }
    }

    public static func chooseFileEnabled(_ kind: OnboardingAssetKind) -> Bool {
        switch kind {
        case .guest:
            return true
        case .k3sAirgap:
            return AirgapPin.bundled.signed.chooseFileEnabled
        case .kubevirtAirgap:
            return KubeVirtAirgapPin.bundled.signed.chooseFileEnabled
        }
    }
}
