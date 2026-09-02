import Foundation

public enum SignedAssetError: Error, Equatable, LocalizedError, Sendable {
    case missingResource
    case invalidPin(String)
    case missingArchive(label: String, path: String)
    case missingSignature(label: String)
    case sha256Mismatch(label: String, expected: String, actual: String)
    case cosignVerifyFailed(label: String)
    case tooLarge(label: String, size: Int64, max: Int64)
    case invalidSignature(label: String)
    case downloadFailed(label: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Asset pin or Cosign public key is missing from the app bundle"
        case .invalidPin(let key):
            return "Asset pin is missing \(key)"
        case .missingArchive(let label, let path):
            return "\(label) missing at \(path). Choose a file…"
        case .missingSignature(let label):
            return "\(label) Cosign signature missing"
        case .sha256Mismatch(let label, _, _):
            return "\(label) SHA-256 mismatch"
        case .cosignVerifyFailed(let label):
            return "\(label) Cosign signature verify failed"
        case .tooLarge(let label, let size, let max):
            return "\(label) is \(size) bytes; size budget is \(max) bytes"
        case .invalidSignature(let label):
            return "\(label) Cosign signature is not valid ECDSA"
        case .downloadFailed(let label, let message):
            return "\(label) download failed: \(message)"
        }
    }
}

/// Host cache for a SHA-256 + keyful Cosign-verified archive.
public struct SignedAssetStore: Sendable {
    public var cacheDirectory: URL
    public var pin: SignedAssetPin
    public var publicKeyPEM: String
    public var label: String

    public init(cacheDirectory: URL, pin: SignedAssetPin, publicKeyPEM: String, label: String) {
        self.cacheDirectory = cacheDirectory
        self.pin = pin
        self.publicKeyPEM = publicKeyPEM
        self.label = label
    }

    public var archiveURL: URL {
        cacheDirectory.appending(path: pin.fileName)
    }

    public var signatureURL: URL {
        cacheDirectory.appending(path: "\(pin.fileName).sig")
    }

    public func cachedFileIfValid() throws -> URL? {
        let file = archiveURL
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
            return nil
        }
        let sig = signatureURL
        guard FileManager.default.fileExists(atPath: sig.path(percentEncoded: false)) else {
            throw SignedAssetError.missingSignature(label: label)
        }
        try verify(file: file, signatureFile: sig)
        return file
    }

    public func importLocalFile(_ source: URL, signature: URL? = nil, fileManager: FileManager = .default) throws -> URL
    {
        let sig = signature ?? source.appendingPathExtension("sig")
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw SignedAssetError.missingArchive(label: label, path: source.path(percentEncoded: false))
        }
        guard fileManager.fileExists(atPath: sig.path(percentEncoded: false)) else {
            throw SignedAssetError.missingSignature(label: label)
        }
        try verify(file: source, signatureFile: sig)
        try AtomicFileReplace.copy(from: source, to: archiveURL, posixPermissions: 0o600, fileManager: fileManager)
        try AtomicFileReplace.copy(from: sig, to: signatureURL, posixPermissions: 0o600, fileManager: fileManager)
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
            throw SignedAssetError.downloadFailed(label: label, message: "HTTP \(status)")
        }
        defer { try? fileManager.removeItem(at: tmp) }
        let sigRemote = remoteSignature ?? pin.url.appendingPathExtension("sig")
        let (sigTmp, sigResponse) = try await session.download(from: sigRemote)
        defer { try? fileManager.removeItem(at: sigTmp) }
        let sigStatus = (sigResponse as? HTTPURLResponse)?.statusCode ?? 200
        if sigStatus < 200 || sigStatus >= 300 {
            throw SignedAssetError.missingSignature(label: label)
        }
        try verify(file: tmp, signatureFile: sigTmp)
        try AtomicFileReplace.copy(from: tmp, to: archiveURL, posixPermissions: 0o600, fileManager: fileManager)
        try AtomicFileReplace.copy(from: sigTmp, to: signatureURL, posixPermissions: 0o600, fileManager: fileManager)
        return archiveURL
    }

    private func verify(file: URL, signatureFile: URL) throws {
        do {
            try AirgapVerifier.verify(
                file: file,
                signatureFile: signatureFile,
                sha256: pin.sha256,
                maxBytes: pin.maxBytes,
                publicKeyPEM: publicKeyPEM
            )
        } catch let error as AirgapError {
            throw mapAirgapError(error)
        }
    }

    private func mapAirgapError(_ error: AirgapError) -> SignedAssetError {
        switch error {
        case .missingArchive(let path):
            return .missingArchive(label: label, path: path)
        case .missingSignature:
            return .missingSignature(label: label)
        case .sha256Mismatch(let expected, let actual):
            return .sha256Mismatch(label: label, expected: expected, actual: actual)
        case .cosignVerifyFailed:
            return .cosignVerifyFailed(label: label)
        case .tooLarge(let size, let max):
            return .tooLarge(label: label, size: size, max: max)
        case .invalidSignature:
            return .invalidSignature(label: label)
        case .downloadFailed(let message):
            return .downloadFailed(label: label, message: message)
        case .missingResource, .invalidPin, .insufficientDisk:
            return .cosignVerifyFailed(label: label)
        }
    }
}
