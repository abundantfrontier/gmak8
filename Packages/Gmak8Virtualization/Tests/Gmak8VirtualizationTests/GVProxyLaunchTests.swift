import Foundation
import Testing

@testable import Gmak8Virtualization

struct GVProxyLaunchTests {
    @Test func argumentsUseUnixgramAndLoopbackOnly() throws {
        let http = URL(fileURLWithPath: "/tmp/gmak8-g.sock")
        let vfkit = URL(fileURLWithPath: "/tmp/gmak8-n.sock")
        let args = try GVProxyLaunch.arguments(httpSocket: http, vfkitSocket: vfkit)
        #expect(
            args == [
                "--listen", "unix:///tmp/gmak8-g.sock",
                "--listen-vfkit", "unixgram:///tmp/gmak8-n.sock",
                "--mtu", "1500",
                "--ssh-port", "-1",
            ])
        #expect(args.contains(where: { $0.contains("unixgram://") }))
        #expect(!args.contains(where: { $0.contains("0.0.0.0") }))
        #expect(!args.joined(separator: " ").contains("0.0.0.0"))
    }

    @Test func argumentsFailWhenVfkitPathExceedsSunPath() {
        let tooLong = URL(fileURLWithPath: "/" + String(repeating: "x", count: 120) + "/n.sock")
        #expect(throws: VirtualMachineError.socketPathTooLong(tooLong)) {
            try GVProxyLaunch.arguments(
                httpSocket: URL(fileURLWithPath: "/tmp/g.sock"),
                vfkitSocket: tooLong
            )
        }
    }
}
