import Foundation

public struct AirgapPin: Equatable, Sendable {
    public static let archiveFileName = "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"
    public static let maxCompressedBytes: Int64 = 500 * 1_024 * 1_024
    public static let githubReleaseMaxBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    public static let guestImagesDirectory = "/mnt/data/rancher/agent/images"

    public var k3sVersion: String
    public var fileName: String
    public var url: URL
    public var sha256: String
    public var maxBytes: Int64
    public var guestImagesDirectory: String

    public init(
        k3sVersion: String,
        fileName: String,
        url: URL,
        sha256: String,
        maxBytes: Int64,
        guestImagesDirectory: String
    ) {
        self.k3sVersion = k3sVersion
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256
        self.maxBytes = maxBytes
        self.guestImagesDirectory = guestImagesDirectory
    }

    public static func loadFromModule() throws -> AirgapPin {
        guard let url = Bundle.module.url(forResource: "k3s-airgap", withExtension: "pin") else {
            throw AirgapError.missingResource
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static let bundled: AirgapPin = {
        do {
            return try loadFromModule()
        } catch {
            return AirgapPin(
                k3sVersion: K3sPin.version,
                fileName: archiveFileName,
                url: URL(
                    string:
                        "https://github.com/k3s-io/k3s/releases/download/v1.33.3%2Bk3s1/k3s-airgap-images-arm64.tar.zst"
                )!,
                sha256: "",
                maxBytes: maxCompressedBytes,
                guestImagesDirectory: guestImagesDirectory
            )
        }
    }()

    public static func parse(_ text: String) throws -> AirgapPin {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        guard let version = values["K3S_VERSION"], !version.isEmpty else {
            throw AirgapError.invalidPin("K3S_VERSION")
        }
        guard let fileName = values["AIRGAP_NAME"], !fileName.isEmpty else {
            throw AirgapError.invalidPin("AIRGAP_NAME")
        }
        guard let urlText = values["AIRGAP_URL"], let url = URL(string: urlText) else {
            throw AirgapError.invalidPin("AIRGAP_URL")
        }
        guard let sha = values["AIRGAP_SHA256"], sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        else {
            throw AirgapError.invalidPin("AIRGAP_SHA256")
        }
        guard let maxText = values["AIRGAP_MAX_BYTES"], let maxBytes = Int64(maxText), maxBytes > 0 else {
            throw AirgapError.invalidPin("AIRGAP_MAX_BYTES")
        }
        let images = values["GUEST_IMAGES_DIR"] ?? guestImagesDirectory
        return AirgapPin(
            k3sVersion: version,
            fileName: fileName,
            url: url,
            sha256: sha.lowercased(),
            maxBytes: maxBytes,
            guestImagesDirectory: images
        )
    }
}

public enum CosignPin {
    public static func loadPublicKeyPEM() throws -> String {
        guard let url = Bundle.module.url(forResource: "cosign", withExtension: "pub") else {
            throw AirgapError.missingResource
        }
        let pem = try String(contentsOf: url, encoding: .utf8)
        guard pem.contains("BEGIN PUBLIC KEY") else {
            throw AirgapError.missingResource
        }
        return pem
    }
}

public enum AirgapError: Error, Equatable, LocalizedError, Sendable {
    case missingResource
    case invalidPin(String)
    case missingArchive(String)
    case missingSignature
    case sha256Mismatch(expected: String, actual: String)
    case cosignVerifyFailed
    case tooLarge(size: Int64, max: Int64)
    case insufficientDisk(needed: Int64, free: UInt64)
    case invalidSignature
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            return "k3s airgap pin or Cosign public key is missing from the app bundle"
        case .invalidPin(let key):
            return "k3s airgap pin is missing \(key)"
        case .missingArchive(let path):
            return
                "k3s airgap archive missing at \(path); first boot will not pull docker.io/rancher. Download or choose a local airgap file."
        case .missingSignature:
            return "k3s airgap Cosign signature missing"
        case .sha256Mismatch:
            return "k3s airgap SHA-256 mismatch"
        case .cosignVerifyFailed:
            return "k3s airgap Cosign signature verify failed"
        case .tooLarge(let size, let max):
            return "k3s airgap archive is \(size) bytes; size budget is \(max) bytes"
        case .insufficientDisk(let needed, let free):
            return "data disk has \(free) bytes free; airgap import needs \(needed) (archive + 20%)"
        case .invalidSignature:
            return "k3s airgap Cosign signature is not valid ECDSA"
        case .downloadFailed(let message):
            return "k3s airgap download failed: \(message)"
        }
    }
}
