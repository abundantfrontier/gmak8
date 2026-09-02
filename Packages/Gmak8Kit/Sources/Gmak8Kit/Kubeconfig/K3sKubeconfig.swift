import Foundation
import Yams

public enum K3sKubeconfigError: Error, Equatable, Sendable {
    case notYAML
    case missingMaterial
}

/// Extracts cert material from guest `/etc/rancher/k3s/k3s.yaml` and rewrites `server:`.
public enum K3sKubeconfig {
    public static func material(from yaml: String, server: String) throws -> KubeconfigMaterial {
        let root: Node
        do {
            guard let node = try Yams.compose(yaml: yaml) else {
                throw K3sKubeconfigError.notYAML
            }
            root = node
        } catch let error as K3sKubeconfigError {
            throw error
        } catch {
            throw K3sKubeconfigError.notYAML
        }
        guard let mapping = root.mapping else {
            throw K3sKubeconfigError.notYAML
        }
        guard let ca = firstString(in: mapping, list: "clusters", nested: "cluster", key: "certificate-authority-data"),
            let cert = firstString(in: mapping, list: "users", nested: "user", key: "client-certificate-data"),
            let key = firstString(in: mapping, list: "users", nested: "user", key: "client-key-data")
        else {
            throw K3sKubeconfigError.missingMaterial
        }
        return KubeconfigMaterial(
            server: server,
            certificateAuthorityData: ca,
            clientCertificateData: cert,
            clientKeyData: key
        )
    }

    public static func localhostMaterial(from yaml: String, port: Int) throws -> KubeconfigMaterial {
        try material(from: yaml, server: "https://127.0.0.1:\(port)")
    }
}

private func firstString(in mapping: Node.Mapping, list: String, nested: String, key: String) -> String? {
    guard let sequence = mapping[Node(list)]?.sequence else {
        return nil
    }
    for item in sequence {
        if let value = item.mapping?[Node(nested)]?.mapping?[Node(key)]?.string, !value.isEmpty {
            return value
        }
    }
    return nil
}
