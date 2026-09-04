import Foundation

public enum ApplicationsBundleInstall {
    public static let destination = URL(fileURLWithPath: "/Applications/gmak8.app")

    public static func isInstalled(at source: URL) -> Bool {
        let path = source.resolvingSymlinksInPath().path(percentEncoded: false)
        let dest = destination.resolvingSymlinksInPath().path(percentEncoded: false)
        return path == dest
    }

    public static func install(
        from source: URL,
        to dest: URL = destination,
        fileManager: FileManager = .default
    ) throws {
        let src = source.resolvingSymlinksInPath()
        if src.path(percentEncoded: false) == dest.resolvingSymlinksInPath().path(percentEncoded: false) {
            return
        }
        if fileManager.fileExists(atPath: dest.path(percentEncoded: false)) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: src, to: dest)
    }
}
