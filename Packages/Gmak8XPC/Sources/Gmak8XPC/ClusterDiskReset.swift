import Foundation
import Gmak8Kit

public protocol ClusterDiskResetting: Sendable {
    func resetDisks() throws
}

public struct NoOpClusterDiskReset: ClusterDiskResetting {
    public init() {}

    public func resetDisks() throws {}
}

public struct HostClusterDiskReset: ClusterDiskResetting {
    public var paths: HostPaths

    public init(paths: HostPaths) {
        self.paths = paths
    }

    public func resetDisks() throws {
        let fileManager = FileManager.default
        for url in [paths.dataImage, paths.osImage, paths.efiNVRAM] {
            let path = url.path(percentEncoded: false)
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}
