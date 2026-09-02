import Foundation

public enum GVProxyLaunch {
    public static let helperName = "gvproxy"
    public static let environmentOverrideKey = "GMAK8_GVPROXY"

    public static func unixListenURI(socket: URL) -> String {
        "unix://\(UnixgramPath.fileSystemPath(socket))"
    }

    public static func vfkitListenURI(socket: URL) -> String {
        "unixgram://\(UnixgramPath.fileSystemPath(socket))"
    }

    /// argv after the executable. `--ssh-port -1` disables gvproxy's default 127.0.0.1:2222→guest:22.
    public static func arguments(
        httpSocket: URL,
        vfkitSocket: URL,
        mtu: Int = GuestNetwork.mtu
    ) throws -> [String] {
        try UnixgramPath.require(httpSocket)
        try UnixgramPath.require(vfkitSocket)
        let args = [
            "--listen", unixListenURI(socket: httpSocket),
            "--listen-vfkit", vfkitListenURI(socket: vfkitSocket),
            "--mtu", "\(mtu)",
            "--ssh-port", "-1",
        ]
        if args.contains(where: { $0.contains(GuestNetwork.anyAddress) }) {
            throw VirtualMachineError.networkFailed("gvproxy argv must not bind \(GuestNetwork.anyAddress)")
        }
        return args
    }

    public static let bringUpRelativePath = "ThirdParty/gvproxy/bin/\(helperName)"

    /// `gmak8.app/Contents/Helpers/gvproxy`, or `Contents/Helpers/gvproxy` next to `Contents/MacOS/gmak8-core`.
    public static func bundledHelperURL(from bundleOrExecutable: URL) -> URL {
        if bundleOrExecutable.pathExtension == "app" {
            return
                bundleOrExecutable
                .appending(path: "Contents", directoryHint: .isDirectory)
                .appending(path: "Helpers", directoryHint: .isDirectory)
                .appending(path: helperName)
        }
        let parent = bundleOrExecutable.deletingLastPathComponent()
        if parent.lastPathComponent == "MacOS" {
            return
                parent
                .deletingLastPathComponent()
                .appending(path: "Helpers", directoryHint: .isDirectory)
                .appending(path: helperName)
        }
        return
            parent
            .appending(path: "gmak8.app", directoryHint: .isDirectory)
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: helperName)
    }

    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        executableURL: URL = Bundle.main.bundleURL,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        if let override = environment[environmentOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }

        let bundled = bundledHelperURL(from: executableURL)
        if isExecutable(bundled, fileManager: fileManager) {
            return bundled
        }

        // Do not search PATH: Homebrew gvproxy is the wrong pin / Team ID.
        if let bringUp = findBringUpHelper(startingAt: executableURL, fileManager: fileManager) {
            return bringUp
        }
        return findBringUpHelper(startingAt: currentDirectory, fileManager: fileManager)
    }

    private static func isExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.isExecutableFile(atPath: UnixgramPath.fileSystemPath(url))
    }

    private static func findBringUpHelper(startingAt url: URL, fileManager: FileManager) -> URL? {
        var dir = url
        if !url.hasDirectoryPath {
            dir = url.deletingLastPathComponent()
        }
        for _ in 0..<10 {
            let candidate = dir.appending(path: bringUpRelativePath)
            if isExecutable(candidate, fileManager: fileManager) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path {
                break
            }
            dir = parent
        }
        return nil
    }
}
