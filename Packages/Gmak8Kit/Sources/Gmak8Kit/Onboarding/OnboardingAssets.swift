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
            return "k3s airgap"
        case .kubevirtAirgap:
            return "KubeVirt airgap"
        }
    }

    public var fileName: String {
        switch self {
        case .guest:
            return GuestAssetPin.bundled.fileName
        case .k3sAirgap:
            return AirgapPin.bundled.fileName
        case .kubevirtAirgap:
            return "gmak8-kubevirt-airgap-1.6.1-arm64.tar.zst"
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
        switch profile {
        case .kubernetes:
            return [.guest, .k3sAirgap]
        case .eureka, .eurekaAPIOnly:
            return [.guest, .k3sAirgap, .kubevirtAirgap]
        }
    }
}
