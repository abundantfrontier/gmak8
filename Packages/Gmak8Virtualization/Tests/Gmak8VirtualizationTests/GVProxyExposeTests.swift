import Foundation
import Testing

@testable import Gmak8Virtualization

struct GVProxyExposeTests {
    @Test func defaultJSONBindsLoopbackNotAnyAddress() throws {
        let ports = GVProxyExposeRequest.defaultPorts
        #expect(ports.count == 3)
        let expected = [
            ("127.0.0.1:6443", "192.168.127.2:6443"),
            ("127.0.0.1:8080", "192.168.127.2:80"),
            ("127.0.0.1:8443", "192.168.127.2:443"),
        ]
        for (request, pair) in zip(ports, expected) {
            let json = String(data: try request.jsonUTF8(), encoding: .utf8)
            try #require(json != nil)
            #expect(json == "{\"local\":\"\(pair.0)\",\"remote\":\"\(pair.1)\"}")
            #expect(json?.contains("127.0.0.1") == true)
            #expect(json?.contains("0.0.0.0") == false)
            #expect(request.local.hasPrefix("\(GuestNetwork.hostLoopback):"))
            #expect(GuestNetwork.forbiddenHostPorts.contains(request.localPort ?? -1) == false)
        }
    }

    @Test func rejectsAnyAddressAndPrivilegedHostPorts() {
        #expect(throws: VirtualMachineError.self) {
            try GVProxyExposeRequest(local: "0.0.0.0:6443", remote: "192.168.127.2:6443")
        }
        #expect(throws: VirtualMachineError.self) {
            try GVProxyExposeRequest(hostPort: 22, guestPort: 22)
        }
        #expect(throws: VirtualMachineError.self) {
            try GVProxyExposeRequest(hostPort: 80, guestPort: 80)
        }
        #expect(throws: VirtualMachineError.self) {
            try GVProxyExposeRequest(hostPort: 443, guestPort: 443)
        }
        #expect(throws: VirtualMachineError.self) {
            try GVProxyExposeRequest(local: "10.0.0.1:6443", remote: "192.168.127.2:6443")
        }
    }
}
