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

        let k3s = try JSONDecoder().decode(
            GuestK3s.self,
            from: Data(#"{"active":true,"version":"v1.33.3+k3s1","data_dir_minor":"1.33","data_dir_exists":true}"#.utf8)
        )
        #expect(k3s.active)
        #expect(k3s.dataDirMinor == "1.33")
        let node = try JSONDecoder().decode(GuestNode.self, from: Data(#"{"ready":true,"name":"gmak8"}"#.utf8))
        #expect(node.ready)
        #expect(node.name == "gmak8")
        let airgap = try JSONDecoder().decode(
            GuestAirgap.self,
            from: Data(#"{"present":true,"files":["gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"],"bytes":24}"#.utf8)
        )
        #expect(airgap.present)
        #expect(airgap.files.count == 1)
        #expect(airgap.bytes == 24)

        let services = try JSONDecoder().decode(
            GuestServiceList.self,
            from: Data(
                #"{"items":[{"namespace":"default","name":"nginx","type":"NodePort","ports":[{"name":"http","port":80,"nodePort":30080,"protocol":"TCP"}]}]}"#
                    .utf8
            )
        )
        #expect(services.items.count == 1)
        #expect(services.items[0].name == "nginx")
        #expect(services.items[0].ports[0].nodePort == 30080)
        #expect(services.items[0].ports[0].protocolName == "TCP")
        let emptyServices = try JSONDecoder().decode(GuestServiceList.self, from: Data(#"{}"#.utf8))
        #expect(emptyServices.items.isEmpty)

        let images = try JSONDecoder().decode(
            GuestImageList.self,
            from: Data(
                #"{"items":[{"id":"sha256:abc","refs":["nginx:dev"],"size_bytes":12,"system":false}]}"#
                    .utf8
            )
        )
        #expect(images.items.count == 1)
        #expect(images.items[0].refs == ["nginx:dev"])
        #expect(images.items[0].sizeBytes == 12)
        let emptyImages = try JSONDecoder().decode(GuestImageList.self, from: Data(#"{}"#.utf8))
        #expect(emptyImages.items.isEmpty)
        let imported = try JSONDecoder().decode(
            GuestImageImport.self,
            from: Data(#"{"digest":"sha256:abc","refs":["nginx:dev"]}"#.utf8)
        )
        #expect(imported.digest == "sha256:abc")
        let pruned = try JSONDecoder().decode(GuestImagePrune.self, from: Data(#"{}"#.utf8))
        #expect(pruned.deleted.isEmpty)

        let mounts = try JSONDecoder().decode(
            GuestHostMountList.self,
            from: Data(
                #"{"items":[{"name":"src","tag":"gmak8-host-src","path":"/mnt/host/src","read_only":true,"mounted":true,"uid":501,"gid":20}]}"#
                    .utf8
            )
        )
        #expect(mounts.items.count == 1)
        #expect(mounts.items[0].readOnly)
        #expect(mounts.items[0].uid == 501)
        #expect(mounts.items[0].gid == 20)
        let sparse = try JSONDecoder().decode(
            GuestHostMountList.self,
            from: Data(#"{"items":[{"name":"src","tag":"gmak8-host-src","path":"/mnt/host/src"}]}"#.utf8)
        )
        #expect(!sparse.items[0].mounted)
        #expect(sparse.items[0].uid == 0)
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

        let kubeconfig = try await client.kubeconfig()
        #expect(String(data: kubeconfig, encoding: .utf8)?.contains("kind: Config") == true)
        let k3s = try await client.k3s()
        #expect(k3s.active)
        #expect(k3s.dataDirMinor == "1.33")
        try await client.startK3s()
        #expect(!(try await client.sshd()).running)
        #expect((try await client.startSSHD()).running)
        #expect(state.sshdStarts == 1)
        #expect(try await client.node().ready)
        let listed = try await client.services()
        #expect(listed.items.count == 1)
        #expect(listed.items[0].name == "nginx")
        #expect(listed.items[0].ports[0].nodePort == 30080)

        let airgap = try await client.airgap()
        #expect(airgap.present)
        state.airgapPresent = false
        #expect(!(try await client.airgap().present))
        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-airgap-fixture-\(UUID().uuidString).tar")
        try Data("tiny-airgap-fixture".utf8).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let imported = try await client.importAirgap(
            fileURL: fixture, name: "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst")
        #expect(imported.present)
        #expect(state.lastAirgapBody == Data("tiny-airgap-fixture".utf8))

        let listedImages = try await client.images()
        #expect(listedImages.items.isEmpty)
        let imageTar = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-image-fixture-\(UUID().uuidString).tar")
        try Data("tiny-oci-tar".utf8).write(to: imageTar)
        defer { try? FileManager.default.removeItem(at: imageTar) }
        let imageImport = try await client.importImage(fileURL: imageTar, name: "nginx.dev.tar")
        #expect(imageImport.digest.hasPrefix("sha256:"))
        #expect(state.lastImageBody == Data("tiny-oci-tar".utf8))
        #expect(try await client.images().items.count == 1)
        let pruned = try await client.pruneImages()
        #expect(pruned.deleted.count == 1)
        #expect(try await client.images().items.isEmpty)
        let kubevirt = try await client.kubevirt()
        #expect(kubevirt.installed)
        #expect(kubevirt.u1Nano)
        #expect((try await client.installKubeVirt()).phase == "Deployed")
        let kubevirtAirgap = try await client.importKubevirtAirgap(
            fileURL: fixture, name: "gmak8-kubevirt-airgap-1.6.2-arm64.tar.zst")
        #expect(kubevirtAirgap.present)
        #expect((try await client.hostMounts()).items.isEmpty)
        #expect((try await client.applyHostMounts()).items.isEmpty)

        state.kubeconfig = nil
        do {
            _ = try await client.kubeconfig()
            Issue.record("expected 404")
        } catch GuestAgentError.httpStatus(let code, _) {
            #expect(code == 404)
        }
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

    @Test func servicesHTTPErrorThrows() async throws {
        let (server, state) = try makeGuestAgentFixture()
        defer { server.stop() }
        state.servicesStatus = 500
        let client = GuestAgentClient(baseURL: server.url)
        do {
            _ = try await client.services()
            Issue.record("expected kubectl failure")
        } catch GuestAgentError.httpStatus(let code, let message) {
            #expect(code == 500)
            #expect(message == "kubectl failed")
        }
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
