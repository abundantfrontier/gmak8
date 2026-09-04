import Foundation
import Testing

@testable import Gmak8Kit

struct EurekaDocsTests {
    @Test func eurekaLocalDocHasRequiredOverrides() throws {
        let text = try String(contentsOf: docs("eureka-local.md"), encoding: .utf8)
        #expect(text.contains("u1.nano"))
        #expect(text.contains("u1.medium"))
        #expect(text.contains("VirtualMachineClusterInstancetype"))
        #expect(text.contains("export KUBECONFIG="))
        #expect(text.contains("$HOME/.local/bin"))
        #expect(text.contains("virtctl port-forward --stdio=true"))
        #expect(text.contains(KubeVirtPin.smokeDiskImage))
        #expect(text.contains("**Not** `quay.io/kubevirt/cirros-container-disk-demo`"))
        #expect(text.contains("192.168.127.2"))
        #expect(text.contains("/apps/afw/admin"))
        #expect(text.contains("k8s_storage_class: local-path"))
        #expect(text.contains("aarch64"))
        #expect(text.contains("proxy_conf"))
        #expect(text.contains("127.0.0.1"))
        #expect(text.contains("gmak8 port-forward"))
        #expect(text.contains("22022"))
        #expect(text.contains("--address 127.0.0.1"))
        #expect(text.contains("one image at a time"))
        #expect(text.lowercased().contains("builderdash"))
        #expect(!text.lowercased().contains("copy the eureka tree"))
        #expect(text.contains("does **not** call gmak8") || text.contains("does not vendor"))
        #expect(KubeVirtAirgapPin.bundled.signed.hasStubDigest)
    }

    @Test func k3sDeltasAndChangelogExist() throws {
        let deltas = try String(contentsOf: docs("k3s-deltas.md"), encoding: .utf8)
        #expect(deltas.contains("data-dir: /mnt/data/rancher"))
        #expect(deltas.contains("default-local-storage-path: /mnt/data/local-path"))
        #expect(deltas.contains("disable-helm-controller"))
        #expect(deltas.contains("write-kubeconfig"))
        #expect(!deltas.contains("disable-coredns"))
        #expect(deltas.contains("CoreDNS"))
        let changelog = try String(
            contentsOf: repoRoot().appending(path: "CHANGELOG.md"), encoding: .utf8)
        #expect(changelog.contains("eureka-local.md"))
        #expect(changelog.contains("k3s-deltas.md"))
    }

    @Test func soakScriptSharesDeferredReason() throws {
        let script = try String(
            contentsOf: repoRoot().appending(path: SoakPlan.scriptFile), encoding: .utf8)
        #expect(script.contains(SoakPlan.virtctlDeferredReason))
        #expect(script.contains("gmak8 port-forward SSH handshake"))
    }

    @Test func kubevirtPackAirgapSelfTest() throws {
        let script = repoRoot().appending(path: "guest/kubevirt/pack-airgap.sh")
        #expect(FileManager.default.isExecutableFile(atPath: script.path(percentEncoded: false)))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path(percentEncoded: false), "--self-test"]
        process.currentDirectoryURL = repoRoot()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "\(out)\(err)")
        #expect((out + err).contains("self-test ok"))
        let text = try String(contentsOf: script, encoding: .utf8)
        #expect(text.contains("skopeo"))
        #expect(!text.lowercased().contains("docker engine"))
        #expect(text.contains("--self-test"))
    }
}

private func docs(_ name: String) -> URL {
    repoRoot().appending(path: "docs").appending(path: name)
}

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
