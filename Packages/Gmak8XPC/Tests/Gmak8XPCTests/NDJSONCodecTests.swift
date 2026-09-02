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
    }

    @Test func encodesOkAndErrorReplies() throws {
        #expect(try utf8Line(EngineReply.ok) == "{\"ok\":true}\n")
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

    @Test func unknownOpIsUnknownOp() {
        switch NDJSONCodec.decodeRequest(line: "{\"op\":\"loadImage\"}") {
        case .failure(let code):
            #expect(code == .unknownOp)
        case .success:
            Issue.record("expected unknown_op")
        }
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
        #expect(try NDJSONCodec.decodeEvent(line: line) == event)
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
