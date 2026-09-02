import CryptoKit
import Foundation

public enum AirgapVerifier {
    public static func requiredFreeBytes(archiveBytes: Int64) -> Int64 {
        if archiveBytes <= 0 {
            return 0
        }
        return archiveBytes + archiveBytes / 5
    }

    public static func fitsOnDataDisk(archiveBytes: Int64, bytesFree: UInt64) -> Bool {
        let needed = requiredFreeBytes(archiveBytes: archiveBytes)
        guard needed >= 0 else {
            return false
        }
        return UInt64(needed) <= bytesFree
    }

    public static func sha256(ofFile url: URL) throws -> String {
        try sha256Digest(ofFile: url).map { String(format: "%02x", $0) }.joined()
    }

    public static func verifySHA256(file: URL, expected: String) throws {
        let actual = try sha256(ofFile: file)
        let want = expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if actual != want {
            throw AirgapError.sha256Mismatch(expected: want, actual: actual)
        }
    }

    public static func verifySize(file: URL, maxBytes: Int64) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if size <= 0 || size > maxBytes {
            throw AirgapError.tooLarge(size: size, max: maxBytes)
        }
        return size
    }

    public static func verifyCosign(file: URL, signature: Data, pem: String) throws {
        let key: P256.Signing.PublicKey
        do {
            key = try P256.Signing.PublicKey(pemRepresentation: pem)
        } catch {
            throw AirgapError.cosignVerifyFailed
        }
        let digest = try sha256Digest(ofFile: file)
        let signatureBytes = signatureBytes(from: signature)
        let ecdsa: P256.Signing.ECDSASignature
        if let der = try? P256.Signing.ECDSASignature(derRepresentation: signatureBytes) {
            ecdsa = der
        } else if let raw = try? P256.Signing.ECDSASignature(rawRepresentation: signatureBytes) {
            ecdsa = raw
        } else {
            throw AirgapError.invalidSignature
        }
        guard key.isValidSignature(ecdsa, for: digest) else {
            throw AirgapError.cosignVerifyFailed
        }
    }

    static func sha256Digest(ofFile url: URL) throws -> SHA256Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1_024) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    public static func verify(
        file: URL,
        signatureFile: URL,
        sha256: String,
        maxBytes: Int64,
        publicKeyPEM: String
    ) throws {
        _ = try verifySize(file: file, maxBytes: maxBytes)
        try verifySHA256(file: file, expected: sha256)
        let signature = try Data(contentsOf: signatureFile)
        try verifyCosign(file: file, signature: signature, pem: publicKeyPEM)
    }

    public static func verify(
        file: URL,
        signatureFile: URL,
        pin: AirgapPin,
        publicKeyPEM: String
    ) throws {
        try verify(
            file: file,
            signatureFile: signatureFile,
            sha256: pin.sha256,
            maxBytes: pin.maxBytes,
            publicKeyPEM: publicKeyPEM
        )
    }

    public static func signatureBytes(from data: Data) -> Data {
        let trimmed =
            String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let decoded = Data(base64Encoded: trimmed), !decoded.isEmpty {
            return decoded
        }
        return data
    }
}
