import Foundation
import Testing

@testable import Gmak8XPC

struct PortForwardTests {
    @Test func virtctlArgvBindsLoopbackOnly() throws {
        let args = try VirtctlPortForward.arguments(
            kind: .vm, namespace: "default", name: "build", local: 2222, remote: 22)
        #expect(
            args == [
                "port-forward",
                "--address", "127.0.0.1",
                "-n", "default",
                "vm/build",
                "2222:22",
            ]
        )
        #expect(!args.contains { $0.contains("0.0.0.0") })
        #expect(!args.contains("22:22"))
    }

    @Test func vmiTargetAndBareSSHPort() throws {
        let (kind, name) = try VirtctlPortForward.parseTarget("vmi/fedora")
        #expect(kind == .vmi)
        #expect(name == "fedora")
        let ports = try VirtctlPortForward.parsePorts("22")
        #expect(ports.local == 2222)
        #expect(ports.remote == 22)
        let explicit = try VirtctlPortForward.parsePorts("2200:22")
        #expect(explicit.local == 2200)
        #expect(explicit.remote == 22)
    }

    @Test func rejectsPodKindEmptyNameAndPrivilegedHostPorts() {
        #expect(throws: PortForwardError.unsupportedKind(.pod)) {
            try VirtctlPortForward.arguments(
                kind: .pod, namespace: "default", name: "x", local: 18080, remote: 8080)
        }
        #expect(throws: PortForwardError.invalidTarget("vm/")) {
            try VirtctlPortForward.parseTarget("vm/")
        }
        #expect(throws: PortForwardError.invalidTarget("pod/x")) {
            try VirtctlPortForward.parseTarget("pod/x")
        }
        #expect(throws: PortForwardError.forbiddenHostPort(22)) {
            try VirtctlPortForward.parsePorts("22:22")
        }
        #expect(throws: PortForwardError.forbiddenHostPort(80)) {
            try VirtctlPortForward.parsePorts("80")
        }
        #expect(throws: PortForwardError.forbiddenHostPort(443)) {
            try VirtctlPortForward.arguments(
                kind: .vm, namespace: "default", name: "x", local: 443, remote: 443)
        }
        #expect(throws: PortForwardError.invalidPort) {
            try VirtctlPortForward.parsePorts("0")
        }
        #expect(throws: PortForwardError.invalidTarget("vm/")) {
            try VirtctlPortForward.arguments(
                kind: .vm, namespace: "default", name: "", local: 2222, remote: 22)
        }
    }

    @Test func bundledHelperURLFromAppAndCore() {
        let app = URL(fileURLWithPath: "/Applications/gmak8.app")
        #expect(
            VirtctlPortForward.bundledHelperURL(from: app).path(percentEncoded: false)
                == "/Applications/gmak8.app/Contents/Helpers/virtctl"
        )
        let core = URL(fileURLWithPath: "/Applications/gmak8.app/Contents/MacOS/gmak8-core")
        #expect(
            VirtctlPortForward.bundledHelperURL(from: core).path(percentEncoded: false)
                == "/Applications/gmak8.app/Contents/Helpers/virtctl"
        )
    }

    @Test func environmentOverrideWins() {
        let url = VirtctlPortForward.resolveExecutable(
            environment: ["GMAK8_VIRTCTL": "/tmp/virtctl-test"],
            fileManager: FileManager.default,
            executableURL: URL(fileURLWithPath: "/Applications/gmak8.app")
        )
        #expect(url?.path(percentEncoded: false) == "/tmp/virtctl-test")
    }

    @Test func l1BridgeIsHighLocalhostNeverHost22() {
        #expect(L1SSHBridge.hostPort == 22_022)
        #expect(L1SSHBridge.guestPort == 22)
        #expect(L1SSHBridge.service == "sshd")
        #expect(!VirtctlPortForward.forbiddenHostPorts.contains(L1SSHBridge.hostPort))
        #expect(VirtctlPortForward.forbiddenHostPorts.contains(22))
    }
}
