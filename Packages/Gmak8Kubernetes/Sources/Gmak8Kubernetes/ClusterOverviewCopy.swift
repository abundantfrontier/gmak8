import Gmak8Kit

public enum ClusterSidebarItem: String, CaseIterable, Identifiable, Sendable, Hashable {
    case cluster
    case workloads
    case kubeVirt
    case images
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cluster:
            return ClusterOverviewCopy.cluster
        case .workloads:
            return ClusterOverviewCopy.workloads
        case .kubeVirt:
            return ClusterOverviewCopy.kubeVirt
        case .images:
            return ClusterOverviewCopy.images
        case .diagnostics:
            return ClusterOverviewCopy.diagnostics
        }
    }

    public static func visible(for profile: Profile) -> [ClusterSidebarItem] {
        allCases.filter { item in
            if item == .kubeVirt {
                return profile != .kubernetes
            }
            return true
        }
    }
}

public enum ClusterOverviewCopy {
    public static let cluster = "Cluster"
    public static let workloads = "Workloads"
    public static let kubeVirt = "KubeVirt"
    public static let images = "Images"
    public static let diagnostics = "Diagnostics"

    public static let controlPlane = "Control plane"
    public static let sqlite = "SQLite"
    public static let readyz = "/readyz"
    public static let apiReady = "Ready"
    public static let apiNotReady = "Not ready"
    public static let node = "Node"
    public static let nodeReady = "Ready"
    public static let nodeNotReady = "Not ready"
    public static let noNode = "No node yet."
    public static let kvmPresent = "/dev/kvm is present"
    public static let kvmMissing = "/dev/kvm is not present"
    public static let kvmUnknown = "/dev/kvm is not probed from this window."
    public static let addons = "Addons"
    public static let addonsPending = "Addons appear when the API is reachable."
    public static let publishedPorts = "Published ports"
    public static let noPublishedPorts = "No NodePorts on 127.0.0.1 yet."
    public static let meters = "Resources"
    public static let context = "context"
    public static let workloadsEmpty = "Apply a manifest, or gmak8 build an image and deploy."
    public static let kubeVirtEmpty =
        "KubeVirt is an Eureka profile addon. It is hidden on the Kubernetes profile."
    public static let imagesEmpty = ImagesCopy.empty
    public static let refresh = "Refresh"
}
