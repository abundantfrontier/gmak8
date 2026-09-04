import Foundation

public enum MkosiWorkingDirectory {
    public static let relativePath = "guest/mkosi"
    public static let configFileName = "mkosi.conf"

    public static func isMkosiDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(
            atPath: url.appending(path: configFileName).path(percentEncoded: false)
        )
    }

    public static func directory(inRepoRoot root: URL) -> URL {
        root.appending(path: relativePath, directoryHint: .isDirectory)
    }

    /// `url` may be the repo root or `guest/mkosi` itself.
    public static func resolved(fromPicked url: URL, fileManager: FileManager = .default) -> URL? {
        if isMkosiDirectory(url, fileManager: fileManager) {
            return url
        }
        let nested = directory(inRepoRoot: url)
        if isMkosiDirectory(nested, fileManager: fileManager) {
            return nested
        }
        return nil
    }

    public static func resolve(
        home: URL,
        savedRepoPath: String? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        var roots: [URL] = []
        if let saved = savedRepoPath?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            roots.append(URL(fileURLWithPath: saved, isDirectory: true))
        }
        roots.append(contentsOf: [
            home.appending(path: "Documents/GitHub/gmak8", directoryHint: .isDirectory),
            home.appending(path: "Documents/gmak8", directoryHint: .isDirectory),
            home.appending(path: "Developer/gmak8", directoryHint: .isDirectory),
            home.appending(path: "src/gmak8", directoryHint: .isDirectory),
        ])
        for root in roots {
            if let found = resolved(fromPicked: root, fileManager: fileManager) {
                return found
            }
        }
        return nil
    }
}
