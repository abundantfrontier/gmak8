import Foundation
import Testing

@testable import Gmak8GuestClient

struct GuestAgentClientTests {
    @Test func portsReserveAgentAndBuildkit() {
        #expect(Gmak8GuestClient.agentVsockPort == 1024)
        #expect(Gmak8GuestClient.buildkitVsockPort == 1025)
    }

    @Test func decodesGoAgentJSON() throws {
        let health = try JSONDecoder().decode(GuestHealth.self, from: Data(#"{"ok":true}"#.utf8))
        #expect(health.ok)

        let disks = try JSONDecoder().decode(
            GuestDisks.self,
            from: Data(
                #"{"gmak8_data":"mounted","kite_data":"mounted","mountpoint":"/mnt/data","label":"GMAK8_DATA","bytes_total":100,"bytes_free":40}"#
                    .utf8
            )
        )
        #expect(disks.gmak8Data == .mounted)
        #expect(disks.kiteData == .mounted)
        #expect(disks.isDataMounted)
        #expect(disks.bytesTotal == 100)
        #expect(disks.bytesFree == 40)

        let unmounted = try JSONDecoder().decode(
            GuestDisks.self,
            from: Data(
                #"{"gmak8_data":"unmounted","kite_data":"unmounted","mountpoint":"/mnt/data","label":"","bytes_total":0,"bytes_free":0}"#
                    .utf8
            )
        )
        #expect(!unmounted.isDataMounted)

        let kvm = try JSONDecoder().decode(GuestKVM.self, from: Data(#"{"kvm":false}"#.utf8))
        #expect(!kvm.kvm)
    }

    @Test func healthJSONDoesNotCarryDiskKeys() throws {
        let health = try JSONDecoder().decode(GuestHealth.self, from: Data(#"{"ok":true}"#.utf8))
        let encoded = try JSONEncoder().encode(health)
        let text = String(data: encoded, encoding: .utf8) ?? ""
        #expect(!text.contains("gmak8_data"))
        #expect(!text.contains("kite_data"))
    }

    @Test func encodesUnixAndRFC3339TimeBodies() throws {
        let unix = try GuestTime.unix(1_756_713_600).encodeBody()
        #expect(String(data: unix, encoding: .utf8) == #"{"unix":1756713600}"#)
        let rfc = try GuestTime.rfc3339("2026-09-01T12:00:00Z").encodeBody()
        #expect(String(data: rfc, encoding: .utf8) == #"{"rfc3339":"2026-09-01T12:00:00Z"}"#)
    }

    @Test func streamClientTalksHTTPWithoutAVM() async throws {
        let (server, state) = try makeGuestAgentFixture()
        defer { server.stop() }

        let client = GuestAgentClient {
            try TCPGuestChannel.connect(host: "127.0.0.1", port: server.port)
        }

        let health = try await client.health()
        #expect(health.ok)

        let disks = try await client.disks()
        #expect(disks.gmak8Data == .mounted)
        #expect(disks.kiteData == .mounted)
        #expect(disks.mountpoint == "/mnt/data")

        state.mounted = false
        let unmounted = try await client.disks()
        #expect(unmounted.gmak8Data == .unmounted)

        let kvm = try await client.kvm()
        #expect(!kvm.kvm)
        state.kvm = true
        #expect(try await client.kvm().kvm)

        try await client.setTime(.unix(1_756_713_600))
        #expect(String(data: state.lastTimeBody, encoding: .utf8) == #"{"unix":1756713600}"#)
        try await client.setTime(.rfc3339("2026-09-01T12:00:00Z"))
        #expect(String(data: state.lastTimeBody, encoding: .utf8) == #"{"rfc3339":"2026-09-01T12:00:00Z"}"#)

        try await client.shutdown()
        #expect(state.shutdowns == 1)
    }

    @Test func urlSessionClientTalksHTTPWithoutAVM() async throws {
        let (server, _) = try makeGuestAgentFixture()
        defer { server.stop() }

        let client = GuestAgentClient(baseURL: server.url)
        let health = try await client.health()
        #expect(health.ok)
        let disks = try await client.disks()
        #expect(disks.isDataMounted)
    }

    @Test func httpErrorSurfacesAgentMessage() async throws {
        let (server, _) = try makeGuestAgentFixture()
        defer { server.stop() }
        let transport = StreamGuestTransport {
            try TCPGuestChannel.connect(host: "127.0.0.1", port: server.port)
        }
        let response = try await transport.send(method: "GET", path: "/missing", body: nil)
        #expect(response.statusCode == 404)
        let body = try JSONDecoder().decode(GuestOK.self, from: response.body)
        #expect(body.ok == false)
        #expect(body.error == "not found")
    }
}
