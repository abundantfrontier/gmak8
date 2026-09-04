import Foundation

public enum ImagesCopy {
    public static let title = "Images"
    public static let empty = "Load an OCI or Docker tarball, or gmak8 build an image."
    public static let filter = "Filter"
    public static let load = "Load…"
    public static let prune = "Prune"
    public static let build = "Build"
    public static let buildUnavailable = "Build arrives with BuildKit."
    public static let showSystem = "Show system images"
    public static let receiving = "Receiving…"
    public static let importing = "Importing into containerd…"
    public static let name = "Name"
    public static let digest = "Digest"
    public static let size = "Size"
    public static let pruneConfirm = "Prune unused node images? System images that are still in use stay."
    public static let guestMissingImages =
        "Guest image has no /images. Rebuild the Debian appliance so the agent can list containerd images."
}

public enum SystemImageMatcher {
    public static func isSystem(refs: [String]) -> Bool {
        refs.contains { ref in
            let lower = ref.lowercased()
            return lower.contains("/rancher/") || lower.hasPrefix("rancher/")
        }
    }
}

public struct FakeNodeImages {
    public static let sample: [NodeImageRow] = [
        NodeImageRow(
            id: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            refs: ["nginx:dev"],
            sizeBytes: 18_874_368,
            system: false
        ),
        NodeImageRow(
            id: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            refs: ["docker.io/rancher/mirrored-pause:3.6"],
            sizeBytes: 26_214_400,
            system: true
        ),
    ]
}

public struct NodeImageRow: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var refs: [String]
    public var sizeBytes: Int64
    public var system: Bool

    public var displayName: String { refs.first ?? id }

    public init(id: String, refs: [String] = [], sizeBytes: Int64 = 0, system: Bool = false) {
        self.id = id
        self.refs = refs
        self.sizeBytes = sizeBytes
        self.system = system
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kib = Double(bytes) / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.1f MiB", mib)
        }
        return String(format: "%.1f GiB", mib / 1024)
    }
}
