import Foundation

/// Cluster/user material written into the private kubeconfig and the `gmak8` stanzas of `~/.kube/config`.
public struct KubeconfigMaterial: Equatable, Sendable {
    public var server: String
    public var certificateAuthorityData: String
    public var clientCertificateData: String
    public var clientKeyData: String

    public init(
        server: String,
        certificateAuthorityData: String,
        clientCertificateData: String,
        clientKeyData: String
    ) {
        self.server = server
        self.certificateAuthorityData = certificateAuthorityData
        self.clientCertificateData = clientCertificateData
        self.clientKeyData = clientKeyData
    }

    public static func localhost(
        port: Int,
        certificateAuthorityData: String,
        clientCertificateData: String,
        clientKeyData: String
    ) -> KubeconfigMaterial {
        KubeconfigMaterial(
            server: "https://127.0.0.1:\(port)",
            certificateAuthorityData: certificateAuthorityData,
            clientCertificateData: clientCertificateData,
            clientKeyData: clientKeyData
        )
    }
}

public enum KubeconfigSpliceError: Error, Equatable, Sendable {
    /// Existing bytes are not a YAML mapping we can read. Callers must not rewrite the file.
    case notYAML
    /// Valid YAML, but not a block kubeconfig we can stanza-splice without rewriting other items.
    case unspliceable
}
