import Foundation
import Gmak8GuestClient

public enum ImagePreflight {
    public static func bytesNeeded(fileSize: Int64) -> UInt64 {
        guard fileSize > 0 else {
            return 0
        }
        let size = UInt64(fileSize)
        return size + size / 5
    }

    public static func hasRoom(fileSize: Int64, bytesFree: UInt64) -> Bool {
        bytesFree >= bytesNeeded(fileSize: fileSize)
    }
}

public enum NodeImageErrors {
    public static let guestMissingImages =
        "Guest image has no /images. Rebuild the Debian appliance so the agent can list containerd images."
    public static let clusterNotRunning = "cluster is not running"

    public static func message(from error: Error) -> String {
        if let guest = error as? GuestAgentError {
            if case .httpStatus(let code, let detail) = guest {
                if code == 404 {
                    return guestMissingImages
                }
                if let detail, !detail.isEmpty {
                    return detail
                }
            }
            return guest.localizedDescription
        }
        return error.localizedDescription
    }
}

public protocol NodeImageRuntime: Sendable {
    func disks() async throws -> GuestDisks
    func list() async throws -> [GuestImage]
    func importImage(
        fileURL: URL,
        name: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestImageImport
    func prune() async throws -> GuestImagePrune
}

public struct NoOpNodeImageRuntime: NodeImageRuntime {
    public init() {}

    public func disks() async throws -> GuestDisks {
        GuestDisks(
            gmak8Data: .unmounted,
            kiteData: .unmounted,
            mountpoint: "/mnt/data",
            label: "",
            bytesTotal: 0,
            bytesFree: 0
        )
    }

    public func list() async throws -> [GuestImage] {
        []
    }

    public func importImage(
        fileURL: URL,
        name: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestImageImport {
        throw ClusterBringUpError(message: "image import is not available")
    }

    public func prune() async throws -> GuestImagePrune {
        GuestImagePrune()
    }
}

public struct GuestNodeImageRuntime: NodeImageRuntime {
    private let makeClient: @Sendable () async throws -> GuestAgentClient

    public init(makeClient: @escaping @Sendable () async throws -> GuestAgentClient) {
        self.makeClient = makeClient
    }

    public func disks() async throws -> GuestDisks {
        try await makeClient().disks()
    }

    public func list() async throws -> [GuestImage] {
        try await makeClient().images().items
    }

    public func importImage(
        fileURL: URL,
        name: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestImageImport {
        try await makeClient().importImage(fileURL: fileURL, name: name, onProgress: onProgress)
    }

    public func prune() async throws -> GuestImagePrune {
        try await makeClient().pruneImages()
    }
}

public final class FakeNodeImageRuntime: NodeImageRuntime, @unchecked Sendable {
    public var disksValue: GuestDisks
    public var images: [GuestImage]
    public var importResult: GuestImageImport
    public var importError: ClusterBringUpError?
    public var pruneResult: GuestImagePrune
    public var importedURLs: [URL] = []
    public var pruneCount = 0
    public var listError: ClusterBringUpError?

    public init(
        disksValue: GuestDisks = GuestDisks(
            gmak8Data: .mounted,
            kiteData: .mounted,
            mountpoint: "/mnt/data",
            label: "GMAK8_DATA",
            bytesTotal: 60 * 1_024 * 1_024 * 1_024,
            bytesFree: 40 * 1_024 * 1_024 * 1_024
        ),
        images: [GuestImage] = [],
        importResult: GuestImageImport = GuestImageImport(
            digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            refs: ["nginx:dev"]
        ),
        pruneResult: GuestImagePrune = GuestImagePrune()
    ) {
        self.disksValue = disksValue
        self.images = images
        self.importResult = importResult
        self.pruneResult = pruneResult
    }

    public func disks() async throws -> GuestDisks {
        disksValue
    }

    public func list() async throws -> [GuestImage] {
        if let listError {
            throw listError
        }
        return images
    }

    public func importImage(
        fileURL: URL,
        name: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestImageImport {
        importedURLs.append(fileURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        onProgress?(0, size)
        onProgress?(size, size)
        if let importError {
            throw importError
        }
        let image = GuestImage(
            id: importResult.digest,
            refs: importResult.refs.isEmpty ? [name] : importResult.refs,
            sizeBytes: size,
            system: false
        )
        if !images.contains(where: { $0.id == image.id }) {
            images.append(image)
        }
        return importResult
    }

    public func prune() async throws -> GuestImagePrune {
        pruneCount += 1
        let deleted = images.filter { !$0.system }.map(\.id)
        images.removeAll { !$0.system }
        if pruneResult.deleted.isEmpty {
            return GuestImagePrune(deleted: deleted)
        }
        return pruneResult
    }
}

enum NodeImageMapping {
    static func nodeImages(_ items: [GuestImage]) -> [NodeImage] {
        items.map { image in
            NodeImage(id: image.id, refs: image.refs, sizeBytes: image.sizeBytes, system: image.system)
        }
    }
}
