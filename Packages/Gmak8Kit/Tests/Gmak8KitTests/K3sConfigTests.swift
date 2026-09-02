import Foundation
import Testing

@testable import Gmak8Kit

struct K3sConfigTests {
    @Test func templateKeepsHelmControllerAndAdminKubeconfig() {
        #expect(K3sConfig.virtioFSTag == "gmak8-config")
        #expect(K3sConfig.yaml.contains("data-dir: /mnt/data/rancher"))
        #expect(K3sConfig.yaml.contains("default-local-storage-path: /mnt/data/local-path"))
        #expect(K3sConfig.yaml.contains("https-listen-port: 6443"))
        #expect(K3sConfig.yaml.contains("node-name: gmak8"))
        #expect(!K3sConfig.yaml.contains("disable-helm-controller:"))
        #expect(!K3sConfig.yaml.contains("write-kubeconfig:"))
        #expect(!K3sConfig.yaml.contains("\ndisable:"))
        #expect(K3sConfig.yaml.contains("  - 127.0.0.1"))
        #expect(K3sConfig.yaml.contains("  - localhost"))
        #expect(K3sConfig.yaml.contains("  - gmak8"))
        #expect(K3sConfig.yaml.contains("  - gmak8.internal"))
        #expect(K3sConfig.yaml.contains("  - 192.168.127.2"))
        #expect(K3sConfig.yaml.contains("cluster-cidr: 10.42.0.0/16"))
        #expect(K3sConfig.yaml.contains("service-cidr: 10.43.0.0/16"))
        #expect(K3sConfig.yaml.contains("cluster-dns: 10.43.0.10"))
    }

    @Test func writeHostFileCreatesK3sConfigYaml() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-k3s-config-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try K3sConfig.writeHostFile(directory: root)
        let dest = root.appending(path: "k3s/config.yaml")
        #expect(try String(contentsOf: dest, encoding: .utf8) == K3sConfig.yaml)
    }
}
