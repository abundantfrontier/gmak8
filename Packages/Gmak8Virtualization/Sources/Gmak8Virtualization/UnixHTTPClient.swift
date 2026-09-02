import Darwin
import Foundation

/// HTTP/1.1 client over a unix domain socket (gvproxy `--listen unix://g.sock`).
public struct UnixHTTPClient: Sendable {
    public var socketURL: URL
    public var timeout: TimeInterval

    public init(socketURL: URL, timeout: TimeInterval = 5) {
        self.socketURL = socketURL
        self.timeout = timeout
    }

    public func expose(_ request: GVProxyExposeRequest) throws {
        if currentlyExposed().contains(where: { $0.local == request.local }) {
            return
        }
        let body = try request.jsonUTF8()
        let response = try perform(method: "POST", path: "/services/forwarder/expose", body: body)
        if (200..<300).contains(response.status) {
            return
        }
        let text = String(data: response.body, encoding: .utf8) ?? ""
        if GVProxyExposeRequest.isAlreadyBoundError(text) {
            return
        }
        throw VirtualMachineError.networkFailed(
            "expose \(request.local) failed (\(response.status)): \(text)"
        )
    }

    public func currentlyExposed() -> [GVProxyExposeRequest] {
        do {
            let response = try perform(method: "GET", path: "/services/forwarder/all")
            guard (200..<300).contains(response.status) else {
                return []
            }
            return (try? JSONDecoder().decode([GVProxyExposeRequest].self, from: response.body)) ?? []
        } catch {
            return []
        }
    }

    public func perform(method: String, path: String, body: Data? = nil) throws -> (status: Int, body: Data) {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixgramPath.posixError("socket", path: UnixgramPath.fileSystemPath(socketURL))
        }
        defer { Darwin.close(fd) }

        try setReceiveTimeout(fd)

        var addr = try UnixgramPath.sockaddr(path: UnixgramPath.fileSystemPath(socketURL))
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            throw UnixgramPath.posixError("connect", path: UnixgramPath.fileSystemPath(socketURL))
        }

        var message = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
        if let body {
            message += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        message += "\r\n"
        var payload = Data(message.utf8)
        if let body {
            payload.append(body)
        }

        try writeAll(fd: fd, data: payload)
        let raw = try readAll(fd: fd)
        return try parseHTTP(raw)
    }

    private func setReceiveTimeout(_ fd: Int32) throws {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        let rc = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        if rc != 0 {
            throw UnixgramPath.posixError("setsockopt", path: UnixgramPath.fileSystemPath(socketURL))
        }
    }

    private func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var sent = 0
            let total = buffer.count
            while sent < total {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: sent), total - sent)
                if n <= 0 {
                    throw UnixgramPath.posixError("write", path: UnixgramPath.fileSystemPath(socketURL))
                }
                sent += n
            }
        }
    }

    private func readAll(fd: Int32) throws -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n == 0 {
                break
            }
            if n < 0 {
                if errno == EINTR {
                    continue
                }
                throw UnixgramPath.posixError("read", path: UnixgramPath.fileSystemPath(socketURL))
            }
            data.append(chunk, count: n)
        }
        return data
    }

    private func parseHTTP(_ data: Data) throws -> (status: Int, body: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VirtualMachineError.networkFailed("gvproxy HTTP response was not UTF-8")
        }
        let parts = text.split(separator: "\r\n\r\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let header = parts.first, let firstLine = header.split(separator: "\r\n").first else {
            throw VirtualMachineError.networkFailed("gvproxy HTTP response missing headers")
        }
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2, let status = Int(tokens[1]) else {
            throw VirtualMachineError.networkFailed("gvproxy HTTP status unreadable: \(firstLine)")
        }
        let body = parts.count > 1 ? Data(parts[1].utf8) : Data()
        return (status, body)
    }
}
