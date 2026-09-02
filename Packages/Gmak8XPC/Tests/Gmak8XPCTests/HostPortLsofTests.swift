import Testing

@testable import Gmak8XPC

struct HostPortLsofTests {
    @Test func argumentsAreArgvAndDoNotUseAShell() {
        #expect(HostPortLsof.executable == "/usr/sbin/lsof")
        #expect(!HostPortLsof.executable.contains("sh"))
        #expect(HostPortLsof.arguments(port: 6443) == ["-nP", "-iTCP:6443", "-sTCP:LISTEN"])
        #expect(HostPortLsof.arguments(port: 30_663) == ["-nP", "-iTCP:30663", "-sTCP:LISTEN"])
        let injected = HostPortLsof.arguments(port: 6443)
        #expect(!injected.contains { $0.contains(";") || $0.contains("|") || $0.contains("`") || $0.contains("$(") })
        #expect(injected.contains { $0 == "-iTCP:6443" })
    }

    @Test func parseReadsPidWithoutEvaluatingCommandText() throws {
        let output = """
            COMMAND     PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
            kubectl    4321 me     8u  IPv4  0x0      0t0  TCP 127.0.0.1:6443 (LISTEN)
            $(rm)      2210 me     9u  IPv4  0x1      0t0  TCP 127.0.0.1:6443 (LISTEN)
            evil;id    9981 me     4u  IPv4  0x2      0t0  TCP *:6443 (LISTEN)
            """
        var capturedExecutable: String?
        var capturedArguments: [String] = []
        let occupants = try HostPortLsof.occupants(port: 6443) { executable, arguments in
            capturedExecutable = executable
            capturedArguments = arguments
            return output
        }
        #expect(capturedExecutable == HostPortLsof.executable)
        #expect(capturedArguments == HostPortLsof.arguments(port: 6443))
        #expect(occupants.map(\.pid) == [4321, 2210, 9981])
        #expect(occupants.map(\.command) == ["kubectl", "$(rm)", "evil;id"])
        #expect(HostPortLsof.occupancyLine(port: 6443, occupants: occupants).contains("in use by pid 4321 (kubectl)"))
        #expect(HostPortLsof.parse("COMMAND PID USER\n", port: 80).isEmpty)
    }

    @Test func probePortsIncludeIngressFallbacks() {
        #expect(
            HostPortLsof.probePorts(kind: .apiPortConflict, collidingNodePorts: [])
                == [RecoveryPorts.api, RecoveryPorts.apiFallback]
        )
        #expect(
            HostPortLsof.probePorts(kind: .ingressPortConflict, collidingNodePorts: [])
                == [
                    RecoveryPorts.http, RecoveryPorts.httpFallback, RecoveryPorts.https,
                    RecoveryPorts.httpsFallback,
                ]
        )
        #expect(HostPortLsof.probePorts(kind: .nodePortCollision, collidingNodePorts: [30_663]) == [30_663])
        #expect(HostPortLsof.probePorts(kind: .vmPanic, collidingNodePorts: [80]).isEmpty)
    }

    @Test func occupancyLinesShowFailureInsteadOfFree() {
        let lines = HostPortLsof.occupancyLines(ports: [8080, 18_080]) { _, _ in
            throw HostPortLsofError.failed(status: 2)
        }
        #expect(lines.count == 2)
        #expect(lines[0].contains("lsof failed"))
        #expect(!lines[0].contains("is free"))
        #expect(lines[1].contains("18080"))
    }
}
