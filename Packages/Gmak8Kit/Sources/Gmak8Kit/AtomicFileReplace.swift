import Foundation

/// chmod on a sibling temp, then publish, so the destination is never world-readable.
public enum AtomicFileReplace {
    public static func write(
        _ data: Data,
        to url: URL,
        posixPermissions: Int = 0o600,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = temporaryURL(for: url)
        do {
            try data.write(to: temp, options: .withoutOverwriting)
            try setPermissions(posixPermissions, at: temp, fileManager: fileManager)
            try publish(temp, to: url, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    public static func copy(
        from source: URL,
        to url: URL,
        posixPermissions: Int = 0o600,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = temporaryURL(for: url)
        do {
            if fileManager.fileExists(atPath: temp.path(percentEncoded: false)) {
                try fileManager.removeItem(at: temp)
            }
            try fileManager.copyItem(at: source, to: temp)
            try setPermissions(posixPermissions, at: temp, fileManager: fileManager)
            try publish(temp, to: url, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    private static func temporaryURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(
            path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
        )
    }

    private static func setPermissions(_ posixPermissions: Int, at url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [.posixPermissions: posixPermissions],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    private static func publish(_ temp: URL, to url: URL, fileManager: FileManager) throws {
        _ = try fileManager.replaceItemAt(
            url,
            withItemAt: temp,
            backupItemName: nil,
            options: .usingNewMetadataOnly
        )
    }
}
