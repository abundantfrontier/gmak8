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
        let sigExists = FileManager.default.fileExists(atPath: sig.path(percentEncoded: false))
        try AirgapVerifier.verify(
            file: file,
            signatureFile: sigExists ? sig : nil,
            sha256: pin.sha256,
            maxBytes: pin.maxBytes,
            publicKeyPEM: publicKeyPEM,
            requireCosign: pin.signed.requiresCosign
        )
        return file
    }

    /// Copy a user-chosen local archive into the host cache after SHA-256 (and Cosign when a `.sig` is present).
    public func importLocalFile(_ source: URL, signature: URL? = nil, fileManager: FileManager = .default) throws -> URL
    {
        let sig = signature ?? source.appendingPathExtension("sig")
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw AirgapError.missingArchive(source.path(percentEncoded: false))
        }
        let sigExists = fileManager.fileExists(atPath: sig.path(percentEncoded: false))
        if pin.signed.requiresCosign, !sigExists {
            throw AirgapError.missingSignature
        }
        try AirgapVerifier.verify(
            file: source,
            signatureFile: sigExists ? sig : nil,
            sha256: pin.sha256,
            maxBytes: pin.maxBytes,
            publicKeyPEM: publicKeyPEM,
            requireCosign: pin.signed.requiresCosign
        )
        try fileManager.createDirectory(at: paths.airgapCacheDirectory, withIntermediateDirectories: true)
        try AtomicFileReplace.copy(from: source, to: archiveURL, posixPermissions: 0o600, fileManager: fileManager)
        if sigExists {
            try AtomicFileReplace.copy(from: sig, to: signatureURL, posixPermissions: 0o600, fileManager: fileManager)
        }
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
        let haveSig = sigStatus >= 200 && sigStatus < 300
        if pin.signed.requiresCosign, !haveSig {
            throw AirgapError.missingSignature
        }
        try AirgapVerifier.verify(
            file: tmp,
            signatureFile: haveSig ? sigTmp : nil,
            sha256: pin.sha256,
            maxBytes: pin.maxBytes,
            publicKeyPEM: publicKeyPEM,
            requireCosign: pin.signed.requiresCosign
        )
        try fileManager.createDirectory(at: paths.airgapCacheDirectory, withIntermediateDirectories: true)
        try AtomicFileReplace.copy(from: tmp, to: archiveURL, posixPermissions: 0o600, fileManager: fileManager)
        if haveSig {
            try AtomicFileReplace.copy(
                from: sigTmp, to: signatureURL, posixPermissions: 0o600, fileManager: fileManager)
        }
        return archiveURL
    }
}
