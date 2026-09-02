import Foundation
import Testing

@testable import Gmak8Kit

struct K3sKubeconfigTests {
    private let guestYAML = """
        apiVersion: v1
        kind: Config
        clusters:
        - cluster:
            certificate-authority-data: CA_DATA
            server: https://127.0.0.1:6443
          name: default
        contexts:
        - context:
            cluster: default
            user: default
          name: default
        current-context: default
        users:
        - name: default
          user:
            client-certificate-data: CERT_DATA
            client-key-data: KEY_DATA
        """

    @Test func rewritesServerToLoopback6443() throws {
        let material = try K3sKubeconfig.localhostMaterial(from: guestYAML, port: 6443)
        #expect(material.server == "https://127.0.0.1:6443")
        #expect(material.certificateAuthorityData == "CA_DATA")
        #expect(material.clientCertificateData == "CERT_DATA")
        #expect(material.clientKeyData == "KEY_DATA")
    }

    @Test func rewritesServerToLoopback16443() throws {
        let yaml = guestYAML.replacingOccurrences(of: "https://127.0.0.1:6443", with: "https://192.168.127.2:6443")
        let material = try K3sKubeconfig.localhostMaterial(from: yaml, port: 16_443)
        #expect(material.server == "https://127.0.0.1:16443")
        #expect(material.certificateAuthorityData == "CA_DATA")
    }

    @Test func applyWritesRewrittenServer() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-k3s-kube-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = KubeconfigStore(
            hostPaths: HostPaths(
                applicationSupport: root.appending(path: "Application Support/dev.gmak8.app"),
                caches: root.appending(path: "Caches/dev.gmak8.app"),
                logs: root.appending(path: "Logs/gmak8")
            ),
            userKubeconfigFile: root.appending(path: ".kube/config"),
            environment: ["KUBECONFIG": "/tmp/do-not-merge"]
        )
        let material = try K3sKubeconfig.localhostMaterial(from: guestYAML, port: 16_443)
        let result = try store.apply(material: material, setCurrentContext: false)
        #expect(!result.didMergeIntoUserConfig)
        let privateYAML = try String(contentsOf: store.privateKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("server: https://127.0.0.1:16443"))
        #expect(!privateYAML.contains("192.168.127.2"))
    }

    @Test func missingCertsAreMissingMaterial() {
        let yaml = """
            apiVersion: v1
            clusters:
            - cluster:
                server: https://127.0.0.1:6443
              name: default
            """
        #expect(throws: K3sKubeconfigError.missingMaterial) {
            _ = try K3sKubeconfig.localhostMaterial(from: yaml, port: 6443)
        }
    }

    @Test func nonYAMLIsRejected() {
        #expect(throws: K3sKubeconfigError.notYAML) {
            _ = try K3sKubeconfig.localhostMaterial(from: "{[", port: 6443)
        }
    }
}
