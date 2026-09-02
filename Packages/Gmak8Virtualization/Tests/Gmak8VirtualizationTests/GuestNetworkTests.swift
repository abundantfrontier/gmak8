import Foundation
import Testing

@testable import Gmak8Virtualization

struct GuestNetworkTests {
    @Test func addressPlanIsPinnedToGvproxyDefaults() {
        #expect(GuestNetwork.subnet == "192.168.127.0/24")
        #expect(GuestNetwork.gatewayIPv4 == "192.168.127.1")
        #expect(GuestNetwork.guestIPv4 == "192.168.127.2")
        #expect(GuestNetwork.guestMACAddress == "5a:94:ef:e4:0c:ee")
        #expect(GuestNetwork.hostLoopback == "127.0.0.1")
        #expect(GuestNetwork.mtu == 1500)
        #expect(GuestNetwork.hostLoopback != GuestNetwork.anyAddress)
        #expect(!GuestNetwork.guestIPv4.contains(GuestNetwork.anyAddress))
        #expect(!GuestNetwork.subnet.contains(GuestNetwork.anyAddress))
    }

    @Test func forbiddenHostPortsArePrivileged() {
        #expect(GuestNetwork.forbiddenHostPorts == [22, 80, 443])
        #expect(!GuestNetwork.forbiddenHostPorts.contains(GuestNetwork.apiHostPort))
        #expect(!GuestNetwork.forbiddenHostPorts.contains(GuestNetwork.httpHostPort))
        #expect(!GuestNetwork.forbiddenHostPorts.contains(GuestNetwork.httpsHostPort))
    }
}
