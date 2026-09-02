import Foundation

/// Shipped k3s data-dir compatibility. v1 does not in-place-upgrade 1.32 data to 1.33.
public struct CompatibilityMatrix: Codable, Equatable, Sendable {
    public var k3s: [String: K3sEntry]

    public struct K3sEntry: Codable, Equatable, Sendable {
        public var dataDirMinorsAccepted: [String]

        public init(dataDirMinorsAccepted: [String]) {
            self.dataDirMinorsAccepted = dataDirMinorsAccepted
        }
    }

    public init(k3s: [String: K3sEntry]) {
        self.k3s = k3s
    }

    public static let jsonUTF8 = Data(
        """
        {"k3s":{"v1.33.3+k3s1":{"dataDirMinorsAccepted":["1.33"]}}}
        """.utf8
    )

    public static let bundled: CompatibilityMatrix = {
        if let decoded = try? JSONDecoder().decode(CompatibilityMatrix.self, from: jsonUTF8) {
            return decoded
        }
        return CompatibilityMatrix(
            k3s: [
                K3sPin.version: K3sEntry(dataDirMinorsAccepted: ["1.33"])
            ]
        )
    }()

    /// Empty or missing data-dir minor is a new install and is accepted.
    public func accepts(
        shippedVersion: String = K3sPin.version,
        dataDirMinor: String?
    ) -> Bool {
        guard let dataDirMinor, !dataDirMinor.isEmpty else {
            return true
        }
        guard let entry = k3s[shippedVersion] else {
            return false
        }
        return entry.dataDirMinorsAccepted.contains(dataDirMinor)
    }

    public func refusalMessage(
        shippedVersion: String = K3sPin.version,
        dataDirMinor: String
    ) -> String {
        let accepted = k3s[shippedVersion]?.dataDirMinorsAccepted.joined(separator: ", ") ?? "none"
        return
            "On-disk k3s data is Kubernetes \(dataDirMinor), but this gmak8 ships \(shippedVersion) (accepts \(accepted)). Reset the cluster or install a matching gmak8/guest pair."
    }
}

public enum K3sPin {
    public static let version = "v1.33.3+k3s1"
}
