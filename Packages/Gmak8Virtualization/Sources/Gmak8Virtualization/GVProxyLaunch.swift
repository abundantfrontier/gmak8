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

    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) -> URL? {
        if let override = environment[environmentOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }

        let helpers = bundle.bundleURL
            .deletingLastPathComponent()
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: helperName)
        if fileManager.isExecutableFile(atPath: UnixgramPath.fileSystemPath(helpers)) {
            return helpers
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appending(path: helperName)
                if fileManager.isExecutableFile(atPath: UnixgramPath.fileSystemPath(candidate)) {
                    return candidate
                }
            }
        }
        return nil
    }
}
