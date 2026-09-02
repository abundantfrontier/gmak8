import Darwin
import Foundation

public struct KubeconfigApplyResult: Equatable, Sendable {
    public var didMergeIntoUserConfig: Bool
    public var exportSnippet: String
    public var privateKubeconfig: URL
    public var userKubeconfig: URL

    public init(
        didMergeIntoUserConfig: Bool,
        exportSnippet: String,
        privateKubeconfig: URL,
        userKubeconfig: URL
    ) {
        self.didMergeIntoUserConfig = didMergeIntoUserConfig
        self.exportSnippet = exportSnippet
        self.privateKubeconfig = privateKubeconfig
        self.userKubeconfig = userKubeconfig
    }
}

public enum KubeconfigError: Error, Equatable, Sendable {
    case userConfigNotYAML(path: String, exportSnippet: String)
    case unspliceableUserConfig(path: String, exportSnippet: String)
    case lockFailed(path: String)
}

/// Private 0600 kubeconfig plus an optional stanza-splice into `~/.kube/config`.
public struct KubeconfigStore: Equatable, Sendable {
    public var hostPaths: HostPaths
    public var userKubeconfigFile: URL
    public var environment: [String: String]

    public init(hostPaths: HostPaths, userKubeconfigFile: URL, environment: [String: String] = [:]) {
        self.hostPaths = hostPaths
        self.userKubeconfigFile = userKubeconfigFile
        self.environment = environment
    }

    public static func current(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> KubeconfigStore {
        KubeconfigStore(
            hostPaths: .current(fileManager: fileManager),
            userKubeconfigFile: fileManager.homeDirectoryForCurrentUser
                .appending(path: ".kube", directoryHint: .isDirectory)
                .appending(path: "config"),
            environment: environment
        )
    }

    public var privateKubeconfigFile: URL {
        hostPaths.kubeconfigFile
    }

    public var exportSnippet: String {
        let privatePath = privateKubeconfigFile.path(percentEncoded: false)
        return "export KUBECONFIG=\"\(privatePath):$KUBECONFIG\""
    }

    public var userKubeconfigLockFile: URL {
        userKubeconfigFile.deletingLastPathComponent().appending(
            path: "\(userKubeconfigFile.lastPathComponent).lock"
        )
    }

    public var userKubeconfigBackupFile: URL {
        userKubeconfigFile.deletingLastPathComponent().appending(
            path: "\(userKubeconfigFile.lastPathComponent).gmak8.bak"
        )
    }

    /// Writes the private kubeconfig. Merges into the user kubeconfig only when `KUBECONFIG` is unset or empty.
    /// `current-context: gmak8` is written to the user file only when `setCurrentContext` is true.
    public func apply(
        material: KubeconfigMaterial,
        setCurrentContext: Bool = false,
        fileManager: FileManager = .default
    ) throws -> KubeconfigApplyResult {
        let privateYAML = KubeconfigSplicer.standaloneDocument(material: material, setCurrentContext: true)
        try fileManager.createDirectory(
            at: privateKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeOwnerReadWriteAtomically(
            Data(privateYAML.utf8),
            to: privateKubeconfigFile,
            fileManager: fileManager
        )

        if !shouldMergeIntoUserConfig {
            return KubeconfigApplyResult(
                didMergeIntoUserConfig: false,
                exportSnippet: exportSnippet,
                privateKubeconfig: privateKubeconfigFile,
                userKubeconfig: userKubeconfigFile
            )
        }

        try mergeIntoUserConfig(material: material, setCurrentContext: setCurrentContext, fileManager: fileManager)
        return KubeconfigApplyResult(
            didMergeIntoUserConfig: true,
            exportSnippet: exportSnippet,
            privateKubeconfig: privateKubeconfigFile,
            userKubeconfig: userKubeconfigFile
        )
    }

    private var shouldMergeIntoUserConfig: Bool {
        guard let value = environment["KUBECONFIG"] else {
            return true
        }
        return value.isEmpty
    }

    private func mergeIntoUserConfig(
        material: KubeconfigMaterial,
        setCurrentContext: Bool,
        fileManager: FileManager
    ) throws {
        let directory = userKubeconfigFile.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let lock = try ExclusiveFileLock(url: userKubeconfigLockFile)
        defer { lock.release() }

        let path = userKubeconfigFile.path(percentEncoded: false)
        let publishURL = try publishURL(for: userKubeconfigFile, fileManager: fileManager)
        if !fileManager.fileExists(atPath: path) && !isSymbolicLink(userKubeconfigFile) {
            let yaml = KubeconfigSplicer.standaloneDocument(
                material: material,
                setCurrentContext: setCurrentContext
            )
            try writeFsyncRename(Data(yaml.utf8), to: publishURL, fileManager: fileManager)
            return
        }

        let existing: String
        do {
            existing = try String(contentsOf: userKubeconfigFile, encoding: .utf8)
        } catch {
            throw KubeconfigError.userConfigNotYAML(path: path, exportSnippet: exportSnippet)
        }

        let spliced: String
        do {
            spliced = try KubeconfigSplicer.splice(
                existing: existing,
                material: material,
                setCurrentContext: setCurrentContext
            )
        } catch KubeconfigSpliceError.notYAML {
            Gmak8Log.k8s.error("user kubeconfig is not YAML; leaving it untouched")
            throw KubeconfigError.userConfigNotYAML(path: path, exportSnippet: exportSnippet)
        } catch KubeconfigSpliceError.unspliceable {
            Gmak8Log.k8s.error("user kubeconfig cannot be stanza-spliced; leaving it untouched")
            throw KubeconfigError.unspliceableUserConfig(path: path, exportSnippet: exportSnippet)
        }

        try backupUserConfig(fileManager: fileManager)
        try writeFsyncRename(Data(spliced.utf8), to: publishURL, fileManager: fileManager)
    }

    private func backupUserConfig(fileManager: FileManager) throws {
        let backup = userKubeconfigBackupFile
        if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
            try fileManager.removeItem(at: backup)
        }
        // Follow the user path so a symlink backup is a content snapshot, not another link.
        let data = try Data(contentsOf: userKubeconfigFile)
        try writeRestrictedFile(data, to: backup, fsync: false)
    }
}

/// Create dest with mode 0600, then replace, so neither the temp nor the published path is world-readable.
private func writeOwnerReadWriteAtomically(_ data: Data, to url: URL, fileManager: FileManager) throws {
    let temp = url.deletingLastPathComponent().appending(
        path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    do {
        try writeRestrictedFile(data, to: temp, fsync: false)
        _ = try fileManager.replaceItemAt(
            url,
            withItemAt: temp,
            backupItemName: nil,
            options: .usingNewMetadataOnly
        )
    } catch {
        try? fileManager.removeItem(at: temp)
        throw error
    }
}

private func writeFsyncRename(_ data: Data, to url: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temp = url.deletingLastPathComponent().appending(
        path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    let tempPath = temp.path(percentEncoded: false)
    let destPath = url.path(percentEncoded: false)
    do {
        try writeRestrictedFile(data, to: temp, fsync: true)
        if rename(tempPath, destPath) != 0 {
            let code = errno
            try? fileManager.removeItem(at: temp)
            throw posixError(code, path: destPath)
        }
    } catch {
        try? fileManager.removeItem(at: temp)
        throw error
    }
}

/// `open(O_CREAT|O_EXCL, 0600)` so the file is never world-readable, including before chmod.
private func writeRestrictedFile(_ data: Data, to url: URL, fsync shouldFsync: Bool) throws {
    let path = url.path(percentEncoded: false)
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
    guard fd >= 0 else {
        throw posixError(errno, path: path)
    }
    defer { close(fd) }
    if fchmod(fd, 0o600) != 0 {
        throw posixError(errno, path: path)
    }
    var remaining = data
    while !remaining.isEmpty {
        let written = remaining.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else {
                return 0
            }
            return write(fd, base, buffer.count)
        }
        if written <= 0 {
            if written < 0, errno == EINTR {
                continue
            }
            throw posixError(written < 0 ? errno : EIO, path: path)
        }
        remaining = remaining.dropFirst(written)
    }
    if shouldFsync, fsync(fd) != 0 {
        throw posixError(errno, path: path)
    }
}

private func posixError(_ code: Int32, path: String) -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
}

private func isSymbolicLink(_ url: URL) -> Bool {
    var info = stat()
    let path = url.path(percentEncoded: false)
    guard lstat(path, &info) == 0 else {
        return false
    }
    return (info.st_mode & S_IFMT) == S_IFLNK
}

/// Follow symlink hops to the ultimate regular file so rename does not replace an intermediate link.
private func publishURL(for url: URL, fileManager: FileManager) throws -> URL {
    var current = url.standardizedFileURL
    var seen: Set<String> = []
    for _ in 0..<32 {
        let path = current.path(percentEncoded: false)
        if seen.contains(path) {
            throw posixError(ELOOP, path: path)
        }
        seen.insert(path)
        guard isSymbolicLink(current) else {
            return current
        }
        let destination = try fileManager.destinationOfSymbolicLink(atPath: path)
        if destination.hasPrefix("/") {
            current = URL(fileURLWithPath: destination).standardizedFileURL
        } else {
            current = current.deletingLastPathComponent().appending(path: destination).standardizedFileURL
        }
    }
    throw posixError(ELOOP, path: url.path(percentEncoded: false))
}

private final class ExclusiveFileLock {
    private let fd: Int32
    private let path: String

    init(url: URL) throws {
        path = url.path(percentEncoded: false)
        fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw KubeconfigError.lockFailed(path: path)
        }
        if flock(fd, LOCK_EX) != 0 {
            close(fd)
            throw KubeconfigError.lockFailed(path: path)
        }
    }

    func release() {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
