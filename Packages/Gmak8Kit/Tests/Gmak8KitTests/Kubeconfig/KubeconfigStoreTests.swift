import Foundation
import Testing

@testable import Gmak8Kit

struct KubeconfigStoreTests {
    private let material = KubeconfigMaterial.localhost(
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

    @Test func writesPrivateFileMode0600WithCurrentContext() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let result = try harness.store.apply(material: material, setCurrentContext: false)
        #expect(result.didMergeIntoUserConfig)
        #expect(result.exportSnippet.contains("export KUBECONFIG=\""))
        #expect(result.exportSnippet.contains(":$KUBECONFIG\""))

        let privateYAML = try String(contentsOf: harness.store.privateKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("current-context: gmak8\n"))
        let privateMode = try posixPermissions(harness.store.privateKubeconfigFile)
        #expect(privateMode == 0o600)

        let userYAML = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        #expect(!userYAML.contains("current-context:"))
        let userMode = try posixPermissions(harness.store.userKubeconfigFile)
        #expect(userMode == 0o600)
    }

    @Test func kubeconfigSetDoesNotMerge() throws {
        let harness = try Harness(environment: ["KUBECONFIG": "/tmp/other-config"])
        defer { harness.tearDown() }

        let marker = "# user-owned, do not touch\n"
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try marker.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        let result = try harness.store.apply(material: material)
        #expect(!result.didMergeIntoUserConfig)
        #expect(result.exportSnippet == harness.store.exportSnippet)
        #expect(try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8) == marker)
        #expect(FileManager.default.fileExists(atPath: harness.store.privateKubeconfigFile.path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(atPath: harness.store.userKubeconfigBackupFile.path(percentEncoded: false)))
    }

    @Test func emptyKubeconfigEnvStillMerges() throws {
        let harness = try Harness(environment: ["KUBECONFIG": ""])
        defer { harness.tearDown() }

        let result = try harness.store.apply(material: material)
        #expect(result.didMergeIntoUserConfig)
        #expect(FileManager.default.fileExists(atPath: harness.store.userKubeconfigFile.path(percentEncoded: false)))
    }

    @Test func nonYAMLUserConfigIsLeftUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let garbage = "this is not: [yaml\n"
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try garbage.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        let path = harness.store.userKubeconfigFile.path(percentEncoded: false)
        let snippet = harness.store.exportSnippet
        #expect(throws: KubeconfigError.userConfigNotYAML(path: path, exportSnippet: snippet)) {
            try harness.store.apply(material: material)
        }
        #expect(try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8) == garbage)
        #expect(FileManager.default.fileExists(atPath: harness.store.privateKubeconfigFile.path(percentEncoded: false)))
    }

    @Test func portRewriteUpdatesPrivateAndMergedServer() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        _ = try harness.store.apply(material: material)
        _ = try harness.store.apply(material: material16443)

        let privateYAML = try String(contentsOf: harness.store.privateKubeconfigFile, encoding: .utf8)
        let userYAML = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        #expect(privateYAML.contains("server: https://127.0.0.1:16443"))
        #expect(!privateYAML.contains("server: https://127.0.0.1:6443"))
        #expect(userYAML.contains("server: https://127.0.0.1:16443"))
        #expect(!userYAML.contains("server: https://127.0.0.1:6443"))
        #expect(
            FileManager.default.fileExists(atPath: harness.store.userKubeconfigBackupFile.path(percentEncoded: false)))
    }

    @Test func backupIsOneGeneration() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        _ = try harness.store.apply(material: material)
        let firstUser = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        _ = try harness.store.apply(material: material16443)
        let backup = try String(contentsOf: harness.store.userKubeconfigBackupFile, encoding: .utf8)
        #expect(backup == firstUser)
        #expect(backup.contains("server: https://127.0.0.1:6443"))
    }

    @Test func jsonUserConfigIsLeftUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let json = "{\"apiVersion\":\"v1\",\"clusters\":[],\"users\":[],\"contexts\":[]}\n"
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        let path = harness.store.userKubeconfigFile.path(percentEncoded: false)
        let snippet = harness.store.exportSnippet
        #expect(throws: KubeconfigError.unspliceableUserConfig(path: path, exportSnippet: snippet)) {
            try harness.store.apply(material: material)
        }
        #expect(try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8) == json)
        #expect(FileManager.default.fileExists(atPath: harness.store.privateKubeconfigFile.path(percentEncoded: false)))
    }

    @Test func commentOnlyUserConfigIsLeftUntouched() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let comments = "# keep me\n"
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try comments.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        let path = harness.store.userKubeconfigFile.path(percentEncoded: false)
        let snippet = harness.store.exportSnippet
        #expect(throws: KubeconfigError.unspliceableUserConfig(path: path, exportSnippet: snippet)) {
            try harness.store.apply(material: material)
        }
        #expect(try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8) == comments)
    }

    @Test func emptyListStubMergesIntoValidYAML() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let stub = try golden("empty-lists.before.yaml")
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try stub.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        _ = try harness.store.apply(material: material)
        let userYAML = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        #expect(userYAML == (try golden("empty-lists.after.yaml")))
        _ = try harness.store.apply(material: material)
        let again = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        #expect(again.contains("name: gmak8"))
        #expect(!again.contains("clusters: []"))
    }

    @Test func symlinkUserConfigWritesThroughToTarget() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let kubeDir = harness.store.userKubeconfigFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: kubeDir, withIntermediateDirectories: true)
        let target = harness.root.appending(path: "real-config")
        let existing = try golden("comments.before.yaml")
        try existing.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: harness.store.userKubeconfigFile.path(percentEncoded: false),
            withDestinationPath: target.path(percentEncoded: false)
        )

        _ = try harness.store.apply(material: material)

        let linkDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: harness.store.userKubeconfigFile.path(percentEncoded: false)
        )
        #expect(linkDestination == target.path(percentEncoded: false))
        #expect(
            try harness.store.userKubeconfigFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)

        let targetYAML = try String(contentsOf: target, encoding: .utf8)
        #expect(targetYAML == (try golden("comments.after.yaml")))
        let backup = try String(contentsOf: harness.store.userKubeconfigBackupFile, encoding: .utf8)
        #expect(backup == existing)
        #expect(
            try harness.store.userKubeconfigBackupFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
                != true)
    }

    @Test func twoHopSymlinkWritesThroughToUltimateTarget() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let kubeDir = harness.store.userKubeconfigFile.deletingLastPathComponent()
        let midDir = harness.root.appending(path: ".config/kube", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: kubeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: midDir, withIntermediateDirectories: true)
        let target = harness.root.appending(path: "dotfiles/config")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = try golden("comments.before.yaml")
        try existing.write(to: target, atomically: true, encoding: .utf8)
        let mid = midDir.appending(path: "config")
        try FileManager.default.createSymbolicLink(
            atPath: mid.path(percentEncoded: false),
            withDestinationPath: target.path(percentEncoded: false)
        )
        try FileManager.default.createSymbolicLink(
            atPath: harness.store.userKubeconfigFile.path(percentEncoded: false),
            withDestinationPath: mid.path(percentEncoded: false)
        )

        _ = try harness.store.apply(material: material)

        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: harness.store.userKubeconfigFile.path(percentEncoded: false)
            ) == mid.path(percentEncoded: false))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: mid.path(percentEncoded: false))
                == target.path(percentEncoded: false))
        #expect(
            try harness.store.userKubeconfigFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try mid.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try String(contentsOf: target, encoding: .utf8) == (try golden("comments.after.yaml")))
        #expect(try String(contentsOf: harness.store.userKubeconfigBackupFile, encoding: .utf8) == existing)
    }

    @Test func spliceIntoExistingUserConfigPreservesForeignStanzas() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        let existing = try golden("comments.before.yaml")
        try FileManager.default.createDirectory(
            at: harness.store.userKubeconfigFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.write(to: harness.store.userKubeconfigFile, atomically: true, encoding: .utf8)

        _ = try harness.store.apply(material: material)
        let userYAML = try String(contentsOf: harness.store.userKubeconfigFile, encoding: .utf8)
        #expect(userYAML == (try golden("comments.after.yaml")))
        #expect(userYAML.contains("current-context: docker-desktop"))
    }

    private func posixPermissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let permissions = attributes[.posixPermissions] as? NSNumber
        return permissions?.intValue ?? -1
    }

    private func golden(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Goldens")
            .appending(path: name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private struct Harness {
    var root: URL
    var store: KubeconfigStore

    init(environment: [String: String] = [:]) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-kubeconfig-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = HostPaths(
            applicationSupport: root.appending(path: "Application Support/dev.gmak8.app", directoryHint: .isDirectory),
            caches: root.appending(path: "Caches/dev.gmak8.app", directoryHint: .isDirectory),
            logs: root.appending(path: "Logs/gmak8", directoryHint: .isDirectory)
        )
        store = KubeconfigStore(
            hostPaths: paths,
            userKubeconfigFile: root.appending(path: ".kube/config"),
            environment: environment
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
