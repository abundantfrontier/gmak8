import Foundation
import Virtualization

public enum EFIVariableStore {
    public static func openOrCreate(at url: URL) throws -> VZEFIVariableStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return VZEFIVariableStore(url: url)
        }
        return try recreate(at: url)
    }

    /// Used on OS replace so firmware boot entries from a previous ESP are not reused.
    public static func recreate(at url: URL) throws -> VZEFIVariableStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try VZEFIVariableStore(creatingVariableStoreAt: url, options: .allowOverwrite)
    }
}
