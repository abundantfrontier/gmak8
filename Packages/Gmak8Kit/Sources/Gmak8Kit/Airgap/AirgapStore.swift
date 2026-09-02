import Foundation

/// Host cache for the pinned k3s airgap archive.
public struct AirgapStore: Sendable {
    public var paths: HostPaths
    public var pin: AirgapPin
    public var publicKeyPEM: String

    public init(paths: HostPaths, pin: AirgapPin = .bundled, publicKeyPEM: String) {
        self.paths = paths
        self.pin = pin
        self.publicKeyPEM = publicKeyPEM
    }

    public var archiveURL: URL {
        paths.airgapCacheDirectory.appending(path: pin.fileName)
    }

    public var signatureURL: URL {
        paths.airgapCacheDirectory.appending(path: "\(pin.fileName).sig")
    }

    public func cachedFileIfValid() throws -> URL? {
        let file = archiveURL
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            return nil
        }
        let sig = signatureURL
        guard FileManager.default.fileExists(atPath: sig.path(percentEncoded: false)) else {
            throw AirgapError.missingSignature
        }
        try AirgapVerifier.verify(file: file, signatureFile: sig, pin: pin, publicKeyPEM: publicKeyPEM)
        return file
    }

    /// Copy a user-chosen local archive into the host cache after SHA-256 and keyful Cosign verify.
    public func importLocalFile(_ source: URL, signature: URL? = nil, fileManager: FileManager = .default) throws -> URL
    {
        let sig = signature ?? source.appendingPathExtension("sig")
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw AirgapError.missingArchive(source.path(percentEncoded: false))
        }
        guard fileManager.fileExists(atPath: sig.path(percentEncoded: false)) else {
            throw AirgapError.missingSignature
        }
        try AirgapVerifier.verify(file: source, signatureFile: sig, pin: pin, publicKeyPEM: publicKeyPEM)
        try fileManager.createDirectory(at: paths.airgapCacheDirectory, withIntermediateDirectories: true)
        try copyOwnerReadWriteAtomically(from: source, to: archiveURL, fileManager: fileManager)
        try copyOwnerReadWriteAtomically(from: sig, to: signatureURL, fileManager: fileManager)
        return archiveURL
    }

    public func download(
        session: URLSession = .shared,
        signatureURL remoteSignature: URL? = nil,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let (tmp, response) = try await session.download(from: pin.url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status < 200 || status >= 300 {
            throw AirgapError.downloadFailed("HTTP \(status)")
        }
        defer { try? fileManager.removeItem(at: tmp) }
        let sigRemote = remoteSignature ?? pin.url.appendingPathExtension("sig")
        let (sigTmp, sigResponse) = try await session.download(from: sigRemote)
        defer { try? fileManager.removeItem(at: sigTmp) }
        let sigStatus = (sigResponse as? HTTPURLResponse)?.statusCode ?? 200
        if sigStatus < 200 || sigStatus >= 300 {
            throw AirgapError.missingSignature
        }
        try AirgapVerifier.verify(file: tmp, signatureFile: sigTmp, pin: pin, publicKeyPEM: publicKeyPEM)
        try fileManager.createDirectory(at: paths.airgapCacheDirectory, withIntermediateDirectories: true)
        try copyOwnerReadWriteAtomically(from: tmp, to: archiveURL, fileManager: fileManager)
        try copyOwnerReadWriteAtomically(from: sigTmp, to: signatureURL, fileManager: fileManager)
        return archiveURL
    }
}

/// chmod 0600 on the temp file before publishing so the cache path is never world-readable.
private func copyOwnerReadWriteAtomically(from source: URL, to dest: URL, fileManager: FileManager) throws {
    try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temp = dest.deletingLastPathComponent().appending(
        path: ".\(dest.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    do {
        if fileManager.fileExists(atPath: temp.path(percentEncoded: false)) {
            try fileManager.removeItem(at: temp)
        }
        try fileManager.copyItem(at: source, to: temp)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temp.path(percentEncoded: false)
        )
        _ = try fileManager.replaceItemAt(
            dest,
            withItemAt: temp,
            backupItemName: nil,
            options: .usingNewMetadataOnly
        )
    } catch {
        try? fileManager.removeItem(at: temp)
        throw error
    }
}
