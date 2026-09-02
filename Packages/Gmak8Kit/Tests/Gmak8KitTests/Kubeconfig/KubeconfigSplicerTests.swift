import Foundation
import Testing

@testable import Gmak8Kit

struct KubeconfigSplicerTests {
    private let material6443 = KubeconfigMaterial.localhost(
        port: 6443,
        certificateAuthorityData: "CA_DATA",
        clientCertificateData: "CERT_DATA",
        clientKeyData: "KEY_DATA"
    )

    private let material16443 = KubeconfigMaterial.localhost(
        port: 16443,
        certificateAuthorityData: "CA_DATA",
        clientCertificateData: "CERT_DATA",
        clientKeyData: "KEY_DATA"
    )

    @Test func standaloneOmitsCurrentContextByDefault() {
        let yaml = KubeconfigSplicer.standaloneDocument(material: material6443, setCurrentContext: false)
        #expect(!yaml.contains("current-context:"))
        #expect(yaml.contains("name: gmak8"))
        #expect(yaml.contains("server: https://127.0.0.1:6443"))
    }

    @Test func standaloneWritesCurrentContextWhenOptedIn() {
        let yaml = KubeconfigSplicer.standaloneDocument(material: material6443, setCurrentContext: true)
        #expect(yaml.contains("current-context: gmak8\n"))
    }

    @Test func commentsExecAndUnknownKeysAreCopiedThrough() throws {
        try assertGolden("comments", material: material6443)
    }

    @Test func execPluginUserIsCopiedThrough() throws {
        try assertGolden("exec-user", material: material6443)
    }

    @Test func multipleContextsAppendGmak8AndKeepOthers() throws {
        try assertGolden("multiple-contexts", material: material6443)
    }

    @Test func currentContextPointingElsewhereIsLeftAlone() throws {
        let after = try KubeconfigSplicer.splice(
            existing: try golden("comments.before.yaml"),
            material: material6443,
            setCurrentContext: false
        )
        #expect(after.contains("current-context: docker-desktop\n"))
        #expect(!after.contains("current-context: gmak8"))
    }

    @Test func currentContextOptInRewritesScalar() throws {
        let after = try KubeconfigSplicer.splice(
            existing: try golden("comments.before.yaml"),
            material: material6443,
            setCurrentContext: true
        )
        #expect(after.contains("current-context: gmak8\n"))
        #expect(!after.contains("current-context: docker-desktop"))
        #expect(after.contains("# keep this file-level comment"))
    }

    @Test func apiPort16443RewritesGmak8Server() throws {
        try assertGolden("port-16443", material: material16443)
        let after = try golden("port-16443.after.yaml")
        #expect(after.contains("server: https://127.0.0.1:16443"))
        #expect(after.contains("server: https://other.example"))
        #expect(!after.contains("server: https://127.0.0.1:6443"))
    }

    @Test func nonYAMLThrows() {
        #expect(throws: KubeconfigSpliceError.notYAML) {
            try KubeconfigSplicer.splice(
                existing: "this is not: [yaml\n",
                material: material6443,
                setCurrentContext: false
            )
        }
    }

    @Test func emptyExistingBecomesStandalone() throws {
        let yaml = try KubeconfigSplicer.splice(existing: "  \n", material: material6443, setCurrentContext: false)
        #expect(yaml == KubeconfigSplicer.standaloneDocument(material: material6443, setCurrentContext: false))
    }

    private func assertGolden(_ name: String, material: KubeconfigMaterial) throws {
        let before = try golden("\(name).before.yaml")
        let expected = try golden("\(name).after.yaml")
        let actual = try KubeconfigSplicer.splice(existing: before, material: material, setCurrentContext: false)
        #expect(actual == expected)
    }

    private func golden(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Goldens")
            .appending(path: name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
