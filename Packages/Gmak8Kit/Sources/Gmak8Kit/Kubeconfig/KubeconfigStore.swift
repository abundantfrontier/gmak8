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
        if !fileManager.fileExists(atPath: path) {
            let yaml = KubeconfigSplicer.standaloneDocument(
                material: material,
                setCurrentContext: setCurrentContext
            )
            try writeFsyncRename(Data(yaml.utf8), to: userKubeconfigFile, fileManager: fileManager)
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
        try writeFsyncRename(Data(spliced.utf8), to: userKubeconfigFile, fileManager: fileManager)
    }

    private func backupUserConfig(fileManager: FileManager) throws {
        let backup = userKubeconfigBackupFile
        if fileManager.fileExists(atPath: backup.path(percentEncoded: false)) {
            try fileManager.removeItem(at: backup)
        }
        try fileManager.copyItem(at: userKubeconfigFile, to: backup)
    }
}

/// chmod 0600 on a sibling temp, then replace, so the published path is never world-readable.
private func writeOwnerReadWriteAtomically(_ data: Data, to url: URL, fileManager: FileManager) throws {
    let temp = url.deletingLastPathComponent().appending(
        path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    do {
        try data.write(to: temp, options: .withoutOverwriting)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temp.path(percentEncoded: false)
        )
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
        try data.write(to: temp, options: .withoutOverwriting)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempPath)
        try fsyncPath(tempPath)
        if rename(tempPath, destPath) != 0 {
            let code = errno
            try? fileManager.removeItem(at: temp)
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSFilePathErrorKey: destPath]
            )
        }
    } catch {
        try? fileManager.removeItem(at: temp)
        throw error
    }
}

private func fsyncPath(_ path: String) throws {
    let fd = open(path, O_RDWR)
    guard fd >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
    }
    defer { close(fd) }
    if fsync(fd) != 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: path])
    }
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
