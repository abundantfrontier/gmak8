import Foundation

public struct AssetLibraryItem: Equatable, Sendable, Hashable, Identifiable {
    public var url: URL
    public var relativePath: String

    public var id: String { relativePath }

    public init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
}

public enum AssetLibrary {
    public static let folderName = "gmak8"
    public static let guestSubdirectory = "guest"
    public static let k3sSubdirectory = "k3s"

    public static func defaultRoot(home: URL) -> URL {
        home.appending(path: folderName, directoryHint: .isDirectory)
    }

    public static func ensureLayout(at root: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appending(path: guestSubdirectory, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appending(path: k3sSubdirectory, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    public static func resolvedRoot(libraryFolderPath: String?, home: URL) -> URL {
        let trimmed = libraryFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return defaultRoot(home: home)
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    public static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let full = url.standardizedFileURL.path(percentEncoded: false)
        if full.hasPrefix(rootPath) {
            var rest = String(full.dropFirst(rootPath.count))
            if rest.hasPrefix("/") {
                rest.removeFirst()
            }
            if !rest.isEmpty {
                return rest
            }
        }
        return url.lastPathComponent
    }

    public static func scan(root: URL, fileManager: FileManager = .default) -> (
        guest: [AssetLibraryItem], k3s: [AssetLibraryItem]
    ) {
        var guest: [AssetLibraryItem] = []
        var k3s: [AssetLibraryItem] = []
        let directories = [
            root,
            root.appending(path: guestSubdirectory, directoryHint: .isDirectory),
            root.appending(path: k3sSubdirectory, directoryHint: .isDirectory),
        ]
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for url in contents {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else {
                    continue
                }
                let name = url.lastPathComponent
                let item = AssetLibraryItem(url: url, relativePath: relativePath(for: url, root: root))
                if GuestOSDiskInstall.looksLikeK3sImagePack(name: name) {
                    k3s.append(item)
                    continue
                }
                if isGuestDiskName(name) {
                    guest.append(item)
                }
            }
        }
        guest.sort { $0.relativePath < $1.relativePath }
        k3s.sort { $0.relativePath < $1.relativePath }
        return (guest, k3s)
    }

    public static func k3sDownloadDestination(root: URL, fileName: String) -> URL {
        root.appending(path: k3sSubdirectory, directoryHint: .isDirectory).appending(path: fileName)
    }

    public static func guestDownloadDestination(root: URL, fileName: String) -> URL {
        root.appending(path: guestSubdirectory, directoryHint: .isDirectory).appending(path: fileName)
    }

    /// Prefer a bootable `.img`/`.raw`. Fall back to a `.zst` that install can decompress.
    public static func preferredGuestDisk(_ items: [AssetLibraryItem]) -> AssetLibraryItem? {
        let bootable = items.filter { GuestOSDiskInstall.containsBootSignature(at: $0.url) }
            .sorted { $0.relativePath < $1.relativePath }
        if let first = bootable.first {
            return first
        }
        return items
            .filter {
                let lower = $0.url.lastPathComponent.lowercased()
                return lower.hasSuffix(".zst") && !GuestOSDiskInstall.looksLikeK3sImagePack(name: $0.url.lastPathComponent)
            }
            .sorted { $0.relativePath < $1.relativePath }
            .first
    }

    private static func isGuestDiskName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if GuestOSDiskInstall.looksLikeK3sImagePack(name: name) {
            return false
        }
        return lower.hasSuffix(".img") || lower.hasSuffix(".raw") || lower.hasSuffix(".raw.zst")
            || (lower.hasSuffix(".zst") && !lower.contains(".tar"))
    }
}
