import Foundation

public struct SignedAssetPin: Equatable, Sendable {
    public var fileName: String
    public var url: URL
    public var sha256: String
    public var maxBytes: Int64

    public init(fileName: String, url: URL, sha256: String, maxBytes: Int64) {
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256
        self.maxBytes = maxBytes
    }

    /// All-zero or empty SHA-256 is a placeholder, not a published digest.
    public var hasStubDigest: Bool {
        let hex = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            return true
        }
        return hex.allSatisfy { $0 == "0" }
    }

    /// Remote fetch: abundantfrontier/gmak8 GitHub Release (Cosign) or official k3s-io GitHub airgap (SHA-256).
    public var remoteDownloadEnabled: Bool {
        !hasStubDigest && (Self.isGmak8SignedReleaseURL(url) || Self.isOfficialK3sReleaseURL(url))
    }

    /// Local import still verifies SHA-256; a placeholder digest can never match.
    public var chooseFileEnabled: Bool {
        !hasStubDigest
    }

    /// gmak8-built Release assets carry a keyful Cosign `.sig`. Official k3s-io airgap is SHA-256 only.
    public var requiresCosign: Bool {
        Self.isGmak8SignedReleaseURL(url)
    }

    public static func isGmak8SignedReleaseURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let github = host == "github.com" || host.hasSuffix(".github.com")
        return github && path.contains("/abundantfrontier/gmak8/") && !path.contains("/k3s-io/")
    }

    public static func isOfficialK3sReleaseURL(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let github = host == "github.com" || host.hasSuffix(".github.com")
        return github && path.contains("/k3s-io/k3s/releases/download/")
    }
}

public struct GuestAssetPin: Equatable, Sendable {
    public static let archiveFileName = "gmak8-guest-0.0.1-arm64.raw.zst"
    public static let maxCompressedBytes: Int64 = 500 * 1_024 * 1_024

    public var version: String
    public var fileName: String
    public var url: URL
    public var sha256: String
    public var maxBytes: Int64

    public init(version: String, fileName: String, url: URL, sha256: String, maxBytes: Int64) {
        self.version = version
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256
        self.maxBytes = maxBytes
    }

    public var signed: SignedAssetPin {
        SignedAssetPin(fileName: fileName, url: url, sha256: sha256, maxBytes: maxBytes)
    }

    public static func loadFromModule() throws -> GuestAssetPin {
        guard let url = Bundle.module.url(forResource: "guest", withExtension: "pin") else {
            throw SignedAssetError.missingResource
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static let bundled: GuestAssetPin = {
        do {
            return try loadFromModule()
        } catch {
            return GuestAssetPin(
                version: Gmak8Kit.version,
                fileName: archiveFileName,
                url: URL(
                    string: "https://github.com/abundantfrontier/gmak8/releases/download/v0.0.1/\(archiveFileName)"
                )!,
                sha256: "",
                maxBytes: maxCompressedBytes
            )
        }
    }()

    public static func parse(_ text: String) throws -> GuestAssetPin {
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
        guard let version = values["GUEST_VERSION"], !version.isEmpty else {
            throw SignedAssetError.invalidPin("GUEST_VERSION")
        }
        guard let fileName = values["GUEST_NAME"], !fileName.isEmpty else {
            throw SignedAssetError.invalidPin("GUEST_NAME")
        }
        guard let urlText = values["GUEST_URL"], let url = URL(string: urlText) else {
            throw SignedAssetError.invalidPin("GUEST_URL")
        }
        guard let sha = values["GUEST_SHA256"], sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        else {
            throw SignedAssetError.invalidPin("GUEST_SHA256")
        }
        guard let maxText = values["GUEST_MAX_BYTES"], let maxBytes = Int64(maxText), maxBytes > 0 else {
            throw SignedAssetError.invalidPin("GUEST_MAX_BYTES")
        }
        return GuestAssetPin(
            version: version,
            fileName: fileName,
            url: url,
            sha256: sha.lowercased(),
            maxBytes: maxBytes
        )
    }
}

extension AirgapPin {
    public var signed: SignedAssetPin {
        SignedAssetPin(fileName: fileName, url: url, sha256: sha256, maxBytes: maxBytes)
    }
}
