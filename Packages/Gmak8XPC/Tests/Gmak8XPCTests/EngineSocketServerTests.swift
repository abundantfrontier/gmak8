import Darwin
import Foundation
import Testing

@testable import Gmak8XPC

struct EngineSocketServerTests {
    @Test func socketIsMode0600AndServesNDJSON() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: harness.socketURL.path(percentEncoded: false)
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let client = try EngineTestClient(socketURL: harness.socketURL)
        defer { client.close() }

        try client.send(.status)
        #expect(try client.readReply() == .ok)
        let status = try client.readEvent()
        if case .status(let payload) = status {
            #expect(payload.state == .stopped)
        } else {
            Issue.record("expected status event")
        }
    }

    @Test func startStopSubscribeAndResetForceOverSocket() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let client = try EngineTestClient(socketURL: harness.socketURL)
        defer { client.close() }

        try client.send(.subscribe)
        #expect(try client.readReply() == .ok)
        let initial = try client.readEvent()
        if case .status(let payload) = initial {
            #expect(payload.state == .stopped)
        } else {
            Issue.record("expected initial status")
        }

        try client.send(.start)
        #expect(try client.readReply() == .ok)
        #expect(try client.readState() == .starting)
        _ = try client.readEvent()
        harness.scheduler.runNext()
        #expect(try client.readState() == .running)

        try client.send(.reset(force: false))
        #expect(try client.readReply() == .error(.confirmationRequired))

        try client.send(.reset(force: true))
        #expect(try client.readReply() == .ok)
        #expect(try client.readState() == .stopped)
    }

    @Test func secondListenerSeesLocked() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let engine = ClusterEngine(scheduler: ManualEngineScheduler())
        #expect(throws: EngineErrorCode.locked) {
            let locked = try EngineSocketServer(
                socketURL: harness.socketURL,
                engine: engine,
                identityResolver: FixedPeerIdentityResolver(teamID: nil),
                daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
            )
            try locked.start()
        }
    }

    @Test func localPeerPIDIsSelfForSameProcessConnection() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let client = try EngineTestClient(socketURL: harness.socketURL)
        defer { client.close() }

        let pid = try LocalPeerPID.processIdentifier(socketFD: client.fd)
        #expect(pid == getpid())
        #expect(LocalPeerPID.option == LOCAL_PEERPID)
        #expect(LocalPeerPID.solLocal == SOL_LOCAL)
    }

    @Test func instanceLockIsExclusiveAndMode0600() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let lockPath = harness.server.instanceLockURL.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: lockPath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let fd = open(lockPath, O_RDWR)
        #expect(fd >= 0)
        defer { Darwin.close(fd) }
        #expect(flock(fd, LOCK_EX | LOCK_NB) != 0)
    }

    @Test func crlfLinesAreAccepted() throws {
        let harness = try SocketHarness()
        defer { harness.stop() }

        let client = try EngineTestClient(socketURL: harness.socketURL)
        defer { client.close() }
        try client.sendRaw("{\"op\":\"status\"}\r\n")
        #expect(try client.readReply() == .ok)
    }

    @Test func unauthorizedWhenTeamIDsDiffer() throws {
        let socketURL = URL(fileURLWithPath: "/tmp/g8-\(getpid())-\(UUID().uuidString.prefix(8)).sock")
        let scheduler = ManualEngineScheduler()
        let engine = ClusterEngine(scheduler: scheduler)
        let server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: "TEAMONLY")
        )
        try server.start()
        defer {
            server.stop()
        }

        let client = try EngineTestClient(socketURL: socketURL)
        defer { client.close() }
        #expect(try client.readReply() == .error(.unauthorized))
    }
}

private final class SocketHarness {
    let socketURL: URL
    let scheduler: ManualEngineScheduler
    let engine: ClusterEngine
    let server: EngineSocketServer

    init() throws {
        socketURL = URL(fileURLWithPath: "/tmp/g8-\(getpid())-\(UUID().uuidString.prefix(8)).sock")
        scheduler = ManualEngineScheduler()
        engine = ClusterEngine(scheduler: scheduler)
        server = try EngineSocketServer(
            socketURL: socketURL,
            engine: engine,
            identityResolver: FixedPeerIdentityResolver(teamID: nil),
            daemonIdentity: PeerIdentity(pid: getpid(), teamID: nil)
        )
        try server.start()
    }

    func stop() {
        server.stop()
    }
}

private final class EngineTestClient {
    let fd: Int32
    private var buffer = Data()
    private var pendingEvents: [EngineEvent] = []

    init(socketURL: URL) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw EngineSocketError.socketFailed(errno: errno)
        }
        var nosigpipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let path = socketURL.path(percentEncoded: false)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.withCString { cString in
                dest.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: path.utf8.count + 1))
            }
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            Darwin.close(fd)
            throw EngineSocketError.bindFailed(errno: errno)
        }
        self.fd = fd
    }

    func send(_ request: EngineRequest) throws {
        let data = try NDJSONCodec.encodeLine(request)
        try writeAll(data)
    }

    func sendRaw(_ line: String) throws {
        guard let data = line.data(using: .utf8) else {
            throw EngineErrorCode.invalidRequest
        }
        try writeAll(data)
    }

    func readReply() throws -> EngineReply {
        while true {
            let line = try readLine()
            if let reply = try? NDJSONCodec.decodeReply(line: line) {
                return reply
            }
            if let event = try? NDJSONCodec.decodeEvent(line: line) {
                pendingEvents.append(event)
                continue
            }
            throw EngineErrorCode.invalidRequest
        }
    }

    func readEvent() throws -> EngineEvent {
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
        }
        while true {
            let line = try readLine()
            if (try? NDJSONCodec.decodeReply(line: line)) != nil {
                continue
            }
            return try NDJSONCodec.decodeEvent(line: line)
        }
    }

    func readState() throws -> ClusterState {
        while true {
            let event = try readEvent()
            if case .status(let status) = event {
                return status.state
            }
        }
    }

    func close() {
        Darwin.close(fd)
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, base + offset, rawBuffer.count - offset)
                if written <= 0 {
                    throw EngineSocketError.socketFailed(errno: errno)
                }
                offset += written
            }
        }
    }

    private func readLine() throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return String(data: Data(lineData), encoding: .utf8) ?? ""
            }
            var chunk = [UInt8](repeating: 0, count: 1024)
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 {
                throw EngineSocketError.socketFailed(errno: errno)
            }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }
}
