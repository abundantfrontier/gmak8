import Foundation

public enum KubeVirtPin {
    public static let version = "v1.6.2"
    public static let cdiVersion = "v1.62.0"
    public static let instancetypesVersion = "v1.4.0"
    public static let featureGates = ["VMExport", "EnableVirtioFsConfigVolumes"]
    public static let smokeInstancetype = "u1.nano"
    public static let smokeInstancetypeKind = "VirtualMachineClusterInstancetype"
    public static let smokeDiskImage = "quay.io/containerdisks/fedora:40"
    public static let localDocs = "docs/eureka-local.md"
    public static let guestYAMLDirectory = "/usr/local/share/gmak8/kubevirt"
    public static let virtctlHelperName = "virtctl"

    public static var displayVersion: String {
        var trimmed = version
        if trimmed.first == "v" {
            trimmed.removeFirst()
        }
        return trimmed
    }
}

public struct VirtctlPin: Equatable, Sendable {
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

    public static func loadFromModule() throws -> VirtctlPin {
        guard let url = Bundle.module.url(forResource: "virtctl", withExtension: "pin") else {
            throw AirgapError.missingResource
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static let bundled: VirtctlPin = {
        (try? loadFromModule())
            ?? VirtctlPin(
                version: KubeVirtPin.version,
                fileName: KubeVirtPin.virtctlHelperName,
                url: URL(
                    string:
                        "https://github.com/kubevirt/kubevirt/releases/download/v1.6.1/virtctl-v1.6.1-darwin-arm64"
                )!,
                sha256: "66767c0c7220123961704e7f41a8f86fc43e98a41ef0d0ff0372f32d31940090",
                maxBytes: 80 * 1_024 * 1_024
            )
    }()

    public static func parse(_ text: String) throws -> VirtctlPin {
        let values = PinFile.parse(text)
        guard let version = values["VIRTCTL_VERSION"], !version.isEmpty else {
            throw AirgapError.invalidPin("VIRTCTL_VERSION")
        }
        guard let fileName = values["VIRTCTL_NAME"], !fileName.isEmpty else {
            throw AirgapError.invalidPin("VIRTCTL_NAME")
        }
        guard let urlText = values["VIRTCTL_URL"], let url = URL(string: urlText) else {
            throw AirgapError.invalidPin("VIRTCTL_URL")
        }
        guard let sha = values["VIRTCTL_SHA256"],
            sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        else {
            throw AirgapError.invalidPin("VIRTCTL_SHA256")
        }
        guard let maxText = values["VIRTCTL_MAX_BYTES"], let maxBytes = Int64(maxText), maxBytes > 0 else {
            throw AirgapError.invalidPin("VIRTCTL_MAX_BYTES")
        }
        return VirtctlPin(
            version: version,
            fileName: fileName,
            url: url,
            sha256: sha.lowercased(),
            maxBytes: maxBytes
        )
    }
}

public struct KubeVirtAirgapPin: Equatable, Sendable {
    public static let archiveFileName = "gmak8-kubevirt-airgap-1.6.2-arm64.tar.zst"
    public static let maxCompressedBytes: Int64 = 1_610_612_736

    public var kubevirtVersion: String
    public var fileName: String
    public var url: URL
    public var sha256: String
    public var maxBytes: Int64

    public init(kubevirtVersion: String, fileName: String, url: URL, sha256: String, maxBytes: Int64) {
        self.kubevirtVersion = kubevirtVersion
        self.fileName = fileName
        self.url = url
        self.sha256 = sha256
        self.maxBytes = maxBytes
    }

    public var signed: SignedAssetPin {
        SignedAssetPin(fileName: fileName, url: url, sha256: sha256, maxBytes: maxBytes)
    }

    public static func loadFromModule() throws -> KubeVirtAirgapPin {
        guard let url = Bundle.module.url(forResource: "kubevirt-airgap", withExtension: "pin") else {
            throw AirgapError.missingResource
        }
        return try parse(String(contentsOf: url, encoding: .utf8))
    }

    public static let bundled: KubeVirtAirgapPin = {
        (try? loadFromModule())
            ?? KubeVirtAirgapPin(
                kubevirtVersion: KubeVirtPin.version,
                fileName: archiveFileName,
                url: URL(
                    string:
                        "https://github.com/abundantfrontier/gmak8/releases/download/v0.0.1/\(archiveFileName)"
                )!,
                sha256: String(repeating: "0", count: 64),
                maxBytes: maxCompressedBytes
            )
    }()

    public static func parse(_ text: String) throws -> KubeVirtAirgapPin {
        let values = PinFile.parse(text)
        guard let version = values["KUBEVIRT_VERSION"], !version.isEmpty else {
            throw AirgapError.invalidPin("KUBEVIRT_VERSION")
        }
        guard let fileName = values["AIRGAP_NAME"], !fileName.isEmpty else {
            throw AirgapError.invalidPin("AIRGAP_NAME")
        }
        guard let urlText = values["AIRGAP_URL"], let url = URL(string: urlText) else {
            throw AirgapError.invalidPin("AIRGAP_URL")
        }
        guard let sha = values["AIRGAP_SHA256"],
            sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        else {
            throw AirgapError.invalidPin("AIRGAP_SHA256")
        }
        guard let maxText = values["AIRGAP_MAX_BYTES"], let maxBytes = Int64(maxText), maxBytes > 0 else {
            throw AirgapError.invalidPin("AIRGAP_MAX_BYTES")
        }
        return KubeVirtAirgapPin(
            kubevirtVersion: version,
            fileName: fileName,
            url: url,
            sha256: sha.lowercased(),
            maxBytes: maxBytes
        )
    }
}

enum PinFile {
    static func parse(_ text: String) -> [String: String] {
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
        return values
    }
}
