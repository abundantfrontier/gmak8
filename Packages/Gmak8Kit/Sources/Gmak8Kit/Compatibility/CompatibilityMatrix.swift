import Foundation

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

    public static func loadFromModule() throws -> CompatibilityMatrix {
        guard let url = Bundle.module.url(forResource: "compatibility-matrix", withExtension: "json") else {
            throw CompatibilityMatrixError.missingResource
        }
        return try JSONDecoder().decode(CompatibilityMatrix.self, from: Data(contentsOf: url))
    }

    public static let bundled: CompatibilityMatrix = {
        if let decoded = try? loadFromModule() {
            return decoded
        }
        return CompatibilityMatrix(
            k3s: [
                K3sPin.version: K3sEntry(dataDirMinorsAccepted: ["1.33"])
            ]
        )
    }()

    /// Existing data with an unreadable minor is refused. Empty data dir is accepted.
    public func accepts(
        shippedVersion: String = K3sPin.version,
        dataDirMinor: String?,
        dataDirExists: Bool
    ) -> Bool {
        if !dataDirExists {
            return true
        }
        guard let dataDirMinor, !dataDirMinor.isEmpty else {
            return false
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
        let seen = dataDirMinor.isEmpty ? "unknown" : dataDirMinor
        return
            "On-disk k3s data is Kubernetes \(seen), but this gmak8 ships \(shippedVersion) (accepts \(accepted)). Reset the cluster or install a matching gmak8/guest pair."
    }
}

public enum CompatibilityMatrixError: Error, Equatable, Sendable {
    case missingResource
}

public enum K3sPin {
    public static let version = "v1.33.3+k3s1"
}
