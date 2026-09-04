import Foundation
import Testing

@testable import Gmak8XPC

struct NDJSONCodecTests {
    @Test func encodesOpsAsSingleLineJSON() throws {
        #expect(try utf8Line(EngineRequest.start) == "{\"op\":\"start\"}\n")
        #expect(try utf8Line(EngineRequest.stop) == "{\"op\":\"stop\"}\n")
        #expect(try utf8Line(EngineRequest.prepareUpdate) == "{\"op\":\"prepareUpdate\"}\n")
        #expect(try utf8Line(EngineRequest.reset(force: true)) == "{\"force\":true,\"op\":\"reset\"}\n")
        #expect(try utf8Line(EngineRequest.reset(force: false)) == "{\"force\":false,\"op\":\"reset\"}\n")
        #expect(try utf8Line(EngineRequest.status) == "{\"op\":\"status\"}\n")
        #expect(try utf8Line(EngineRequest.subscribe) == "{\"op\":\"subscribe\"}\n")
        #expect(try utf8Line(EngineRequest.imageList) == "{\"op\":\"imageList\"}\n")
        #expect(try utf8Line(EngineRequest.imagePrune) == "{\"op\":\"imagePrune\"}\n")
        let loaded = try utf8Line(EngineRequest.loadImage(path: "/tmp/foo.tar"))
        #expect(loaded.contains("\"op\":\"loadImage\""))
        #expect(loaded.contains("foo.tar"))
        #expect(
            try NDJSONCodec.decode(EngineRequest.self, line: loaded) == .loadImage(path: "/tmp/foo.tar")
        )
        let forward = try utf8Line(
            EngineRequest.portForwardStart(
                kind: .vmi, namespace: "default", name: "build", local: 2222, remote: 22)
        )
        #expect(
            forward
                == "{\"kind\":\"vmi\",\"local\":2222,\"name\":\"build\",\"ns\":\"default\",\"op\":\"portForwardStart\",\"remote\":22}\n"
        )
        #expect(
            try NDJSONCodec.decode(EngineRequest.self, line: forward)
                == .portForwardStart(
                    kind: .vmi, namespace: "default", name: "build", local: 2222, remote: 22)
        )
        #expect(
            try utf8Line(EngineRequest.portForwardStop(id: "pf-1")) == "{\"id\":\"pf-1\",\"op\":\"portForwardStop\"}\n"
        )
    }

    @Test func encodesOkAndErrorReplies() throws {
        #expect(try utf8Line(EngineReply.ok) == "{\"ok\":true}\n")
        #expect(try utf8Line(EngineReply.started(id: "pf-1")) == "{\"id\":\"pf-1\",\"ok\":true}\n")
        #expect(
            try NDJSONCodec.decodeReply(line: "{\"ok\":true,\"id\":\"pf-1\"}") == .started(id: "pf-1")
        )
        #expect(try utf8Line(EngineReply.error(.conflict)) == "{\"error\":\"conflict\"}\n")
        #expect(
            try utf8Line(EngineReply.error(.confirmationRequired)) == "{\"error\":\"confirmation_required\"}\n"
        )
        #expect(try utf8Line(EngineReply.error(.translocated)) == "{\"error\":\"translocated\"}\n")
        #expect(try utf8Line(EngineReply.error(.locked)) == "{\"error\":\"locked\"}\n")
        #expect(
            try utf8Line(EngineReply.error(.virtualizationUnsupported))
                == "{\"error\":\"virtualization_unsupported\"}\n"
        )
        #expect(
            try utf8Line(EngineReply.error(.unavailable, message: NodeImageErrors.guestMissingImages))
                .contains("\"error\":\"unavailable\"")
        )
        #expect(
            try NDJSONCodec.decodeReply(
                line: "{\"error\":\"unavailable\",\"message\":\"Guest image has no /images.\"}"
            ) == .error(.unavailable, message: "Guest image has no /images.")
        )
    }

    @Test func decodesOpsIncludingResetWithoutForce() throws {
        #expect(try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"start\"}") == .start)
        #expect(try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"reset\"}\n") == .reset(force: false))
        #expect(
            try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"reset\",\"force\":true}")
                == .reset(
                    force: true
                )
        )
    }

    @Test func unknownOpIsUnknownOp() throws {
        switch NDJSONCodec.decodeRequest(line: "{\"op\":\"notARealOp\"}") {
        case .failure(let code):
            #expect(code == .unknownOp)
        case .success:
            Issue.record("expected unknown_op")
        }
        #expect(
            try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"portForwardStart\"}")
                == .portForwardStart(kind: .pod, namespace: "default", name: "", local: 0, remote: 0)
        )
    }

    @Test func invalidJSONIsInvalidRequest() {
        switch NDJSONCodec.decodeRequest(line: "not-json") {
        case .failure(let code):
            #expect(code == .invalidRequest)
        case .success:
            Issue.record("expected invalid_request")
        }
    }

    @Test func statusEventRoundTripIncludesNulls() throws {
        let event = EngineEvent.status(
            EngineStatus(
                state: .stopped,
                step: nil,
                apiEndpoint: nil,
                vm: VMMetrics(),
                nestedVirt: false,
                lastError: nil,
                publishedPorts: [],
                imageJob: nil
            )
        )
        let line = try utf8Line(event)
        #expect(line.contains("\"type\":\"status\""))
        #expect(line.contains("\"state\":\"stopped\""))
        #expect(line.contains("\"step\":null"))
        #expect(line.contains("\"apiEndpoint\":null"))
        #expect(line.contains("\"lastError\":null"))
        #expect(line.contains("\"imageJob\":null"))
        #expect(line.contains("\"publishedPorts\":[]"))
        #expect(line.contains("\"nestedVirt\":false"))
        #expect(line.contains("\"kvmPresent\":null"))
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
    }

    @Test func statusEventRoundTripIncludesKvmPresent() throws {
        let event = EngineEvent.status(
            EngineStatus(state: .running, nestedVirt: true, kvmPresent: true)
        )
        let line = try utf8Line(event)
        #expect(line.contains("\"nestedVirt\":true"))
        #expect(line.contains("\"kvmPresent\":true"))
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
        let legacy = #"{"type":"status","state":"running","nestedVirt":true}"#
        let decoded = try NDJSONCodec.decodeEvent(line: legacy)
        guard case .status(let status) = decoded else {
            Issue.record("expected status")
            return
        }
        #expect(status.nestedVirt)
        #expect(status.kvmPresent == nil)
    }

    @Test func publishedPortRoundTripIncludesCollisionModel() throws {
        let port = PublishedPort(
            service: "nginx",
            namespace: "default",
            port: 80,
            nodePort: 30080,
            hostPort: 30080,
            guestPort: 30080,
            hostURL: "http://127.0.0.1:30080",
            collision: .collision
        )
        let event = EngineEvent.status(
            EngineStatus(state: .running, publishedPorts: [port])
        )
        let line = try utf8Line(event)
        #expect(line.contains("\"service\":\"nginx\""))
        #expect(line.contains("\"nodePort\":30080"))
        #expect(line.contains("\"hostURL\""))
        #expect(line.contains("127.0.0.1:30080"))
        #expect(line.contains("\"collision\":\"collision\""))
        #expect(!line.contains("0.0.0.0"))
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)

        let legacy = try JSONDecoder().decode(
            PublishedPort.self,
            from: Data(#"{"service":"nginx","hostPort":30080,"guestPort":30080}"#.utf8)
        )
        #expect(legacy.hostPort == 30080)
        #expect(legacy.guestPort == 30080)
        #expect(legacy.collision == .published)
        #expect(legacy.hostURL == "http://127.0.0.1:30080")
    }

    @Test func imageJobRoundTrip() throws {
        let event = EngineEvent.status(
            EngineStatus(
                state: .starting,
                step: "airgap",
                imageJob: ImageJobStatus(bytesReceived: 12, bytesTotal: 24)
            )
        )
        let line = try utf8Line(event)
        #expect(line.contains("\"step\":\"airgap\""))
        #expect(line.contains("\"bytesReceived\":12"))
        #expect(line.contains("\"bytesTotal\":24"))
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
    }

    @Test func loadImageDecodesPathAndEmptyPath() throws {
        #expect(
            try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"loadImage\",\"path\":\"/tmp/a.tar\"}")
                == .loadImage(path: "/tmp/a.tar")
        )
        #expect(try NDJSONCodec.decode(EngineRequest.self, line: "{\"op\":\"loadImage\"}") == .loadImage(path: ""))
    }

    @Test func imagesEventRoundTrip() throws {
        let event = EngineEvent.images(
            NodeImageList(items: [
                NodeImage(id: "sha256:abc", refs: ["nginx:dev"], sizeBytes: 12, system: false)
            ])
        )
        let line = try utf8Line(event)
        #expect(line.contains("\"type\":\"images\""))
        #expect(line.contains("\"nginx:dev\""))
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
    }

    @Test func logEventRoundTrip() throws {
        let event = EngineEvent.log(source: .engine, line: "start accepted")
        let line = try utf8Line(event)
        #expect(line == "{\"line\":\"start accepted\",\"source\":\"engine\",\"type\":\"log\"}\n")
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
    }

    @Test func decodeRequestTrimsCRLF() {
        switch NDJSONCodec.decodeRequest(line: "{\"op\":\"status\"}\r") {
        case .success(let request):
            #expect(request == .status)
        case .failure:
            Issue.record("expected status")
        }
    }

    @Test func clusterStateRawValuesMatchProtocol() {
        #expect(
            ClusterState.allCases.map(\.rawValue) == [
                "stopped", "starting", "running", "degraded", "paused", "stopping", "failed",
            ])
    }

    private func utf8Line<T: Encodable>(_ value: T) throws -> String {
        let data = try NDJSONCodec.encodeLine(value)
        let text = String(data: data, encoding: .utf8)
        try #require(text != nil)
        return text!
    }
}
