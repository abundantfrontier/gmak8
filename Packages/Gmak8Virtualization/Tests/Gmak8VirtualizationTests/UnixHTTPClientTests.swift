import Darwin
import Foundation
import Testing

@testable import Gmak8Virtualization

struct UnixHTTPClientTests {
    @Test func postsExposeJSONToUnixSocket() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "g.sock")
        try UnixgramPath.require(socket)

        let recorded = RequestBox()
        let server = try LoopbackHTTPServer(socketURL: socket) { request in
            recorded.append(request)
            if request.contains("GET /services/forwarder/all") {
                return
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[]"
            }
            return "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
        }
        defer { server.stop() }

        let client = UnixHTTPClient(socketURL: socket, timeout: 2)
        let expose = try GVProxyExposeRequest(hostPort: 6443, guestPort: 6443)
        try client.expose(expose)
        let joined = recorded.joined
        #expect(joined.contains("POST /services/forwarder/expose"))
        #expect(joined.contains("127.0.0.1:6443"))
        #expect(joined.contains("192.168.127.2:6443"))
        #expect(!joined.contains("0.0.0.0"))
    }

    @Test func exposeTreatsAlreadyBoundAsSuccess() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "g.sock")
        try UnixgramPath.require(socket)
        let server = try LoopbackHTTPServer(socketURL: socket) { request in
            if request.contains("GET /services/forwarder/all") {
                return
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[]"
            }
            return
                "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\nproxy already running"
        }
        defer { server.stop() }
        let client = UnixHTTPClient(socketURL: socket, timeout: 2)
        try client.expose(try GVProxyExposeRequest(hostPort: 6443, guestPort: 6443))
    }

    @Test func exposeDoesNotTreatAddressInUseAsSuccess() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "g.sock")
        try UnixgramPath.require(socket)
        let server = try LoopbackHTTPServer(socketURL: socket) { request in
            if request.contains("GET /services/forwarder/all") {
                return
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[]"
            }
            return
                "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\n\r\nlisten tcp 127.0.0.1:6443: bind: address already in use"
        }
        defer { server.stop() }
        let client = UnixHTTPClient(socketURL: socket, timeout: 2)
        #expect(throws: VirtualMachineError.self) {
            try client.expose(try GVProxyExposeRequest(hostPort: 6443, guestPort: 6443))
        }
    }

    @Test func sameLocalDifferentRemoteIsCollisionNotIdempotent() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "g.sock")
        try UnixgramPath.require(socket)
        let server = try LoopbackHTTPServer(socketURL: socket) { request in
            if request.contains("GET /services/forwarder/all") {
                return
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n[{\"local\":\"127.0.0.1:8080\",\"remote\":\"192.168.127.2:80\"}]"
            }
            return "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nOK"
        }
        defer { server.stop() }
        let client = UnixHTTPClient(socketURL: socket, timeout: 2)
        #expect(throws: VirtualMachineError.self) {
            try client.expose(try GVProxyExposeRequest(hostPort: 8080, guestPort: 8080))
        }
    }

    @Test func unexposePostsLocalLoopback() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appending(path: "g.sock")
        try UnixgramPath.require(socket)
        let recorded = RequestBox()
        let server = try LoopbackHTTPServer(socketURL: socket) { request in
            recorded.append(request)
            return "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nOK"
        }
        defer { server.stop() }
        let client = UnixHTTPClient(socketURL: socket, timeout: 2)
        try client.unexpose(hostPort: 30080)
        let joined = recorded.joined
        #expect(joined.contains("POST /services/forwarder/unexpose"))
        #expect(joined.contains("127.0.0.1:30080"))
        #expect(!joined.contains("0.0.0.0"))
    }
}

private final class RequestBox: @unchecked Sendable {
    private var parts: [String] = []
    var joined: String { parts.joined(separator: "\n") }
    func append(_ body: String) {
        parts.append(body)
    }
}

private final class LoopbackHTTPServer: @unchecked Sendable {
    private let fd: Int32
    private var running = true
    private let queue = DispatchQueue(label: "gmak8.http.test")

    init(socketURL: URL, handler: @escaping @Sendable (String) -> String) throws {
        try? FileManager.default.removeItem(at: socketURL)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixgramPath.posixError("socket", path: UnixgramPath.fileSystemPath(socketURL))
        }
        var addr = try UnixgramPath.sockaddr(path: UnixgramPath.fileSystemPath(socketURL))
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bound != 0 || Darwin.listen(fd, 1) != 0 {
            Darwin.close(fd)
            throw UnixgramPath.posixError("listen", path: UnixgramPath.fileSystemPath(socketURL))
        }
        self.fd = fd
        queue.async { [weak self] in
            guard let self else {
                return
            }
            while self.running {
                let client = Darwin.accept(fd, nil, nil)
                if client < 0 {
                    continue
                }
                var chunk = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(client, &chunk, chunk.count)
                if n > 0 {
                    let request = String(decoding: chunk.prefix(Int(n)), as: UTF8.self)
                    let response = Array(handler(request).utf8)
                    _ = response.withUnsafeBytes { buffer in
                        Darwin.write(client, buffer.baseAddress, response.count)
                    }
                }
                Darwin.close(client)
            }
        }
    }

    func stop() {
        running = false
        Darwin.close(fd)
    }
}
