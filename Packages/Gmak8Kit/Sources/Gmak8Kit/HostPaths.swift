import Darwin
import Foundation

/// Host-side directories and sockets. Unixgram sockets live under Caches because Application Support
/// paths can exceed Darwin `sun_path`.
public struct HostPaths: Equatable, Sendable {
    /// `sockaddr_un.sun_path` on Darwin, including the trailing NUL.
    public static let unixgramSunPathByteCount = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    public var applicationSupport: URL
    public var caches: URL
    public var logs: URL

    public init(applicationSupport: URL, caches: URL, logs: URL) {
        self.applicationSupport = applicationSupport
        self.caches = caches
        self.logs = logs
    }

    public static func current(fileManager: FileManager = .default) -> HostPaths {
        let applicationSupportRoot = userDirectory(
            .applicationSupportDirectory,
            fileManager: fileManager,
            fallback: "Library/Application Support"
        )
        let cachesRoot = userDirectory(
            .cachesDirectory,
            fileManager: fileManager,
            fallback: "Library/Caches"
        )
        let libraryRoot = userDirectory(
            .libraryDirectory,
            fileManager: fileManager,
            fallback: "Library"
        )

        return HostPaths(
            applicationSupport: applicationSupportRoot.appending(
                path: Gmak8Kit.bundleIdentifier,
                directoryHint: .isDirectory
            ),
            caches: cachesRoot.appending(
                path: Gmak8Kit.bundleIdentifier,
                directoryHint: .isDirectory
            ),
            logs:
                libraryRoot
                .appending(path: "Logs", directoryHint: .isDirectory)
                .appending(path: "gmak8", directoryHint: .isDirectory)
        )
    }

    public var settingsFile: URL {
        applicationSupport.appending(path: "settings.json")
    }

    public var engineSocket: URL {
        applicationSupport.appending(path: "engine.sock")
    }

    public var kubeconfigFile: URL {
        applicationSupport.appending(path: "kubeconfig")
    }

    public var vmDirectory: URL {
        applicationSupport.appending(path: "vm", directoryHint: .isDirectory)
    }

    public var osImage: URL {
        vmDirectory.appending(path: "os.img")
    }

    public var dataImage: URL {
        vmDirectory.appending(path: "data.img")
    }

    public var efiNVRAM: URL {
        vmDirectory.appending(path: "efi-nvram.bin")
    }

    public var serialLog: URL {
        vmDirectory.appending(path: "serial.log")
    }

    public var gvproxyLog: URL {
        logs.appending(path: "gvproxy.log")
    }

    public var vfkitSocket: URL {
        caches.appending(path: "n.sock")
    }

    public var gvproxySocket: URL {
        caches.appending(path: "g.sock")
    }

    public var buildkitSocket: URL {
        caches.appending(path: "buildkit.sock")
    }

    public static func unixgramPathFits(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else {
                return false
            }
            return strlen(pointer) + 1 <= unixgramSunPathByteCount
        }
    }
}

private func userDirectory(
    _ directory: FileManager.SearchPathDirectory,
    fileManager: FileManager,
    fallback: String
) -> URL {
    if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
        return url
    }
    return fileManager.homeDirectoryForCurrentUser.appending(path: fallback, directoryHint: .isDirectory)
}
