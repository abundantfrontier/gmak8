import Darwin
import Foundation

final class LoopbackHTTPServer: @unchecked Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        var body: Data
    }

    struct Response: Sendable {
        var status: Int
        var body: Data

        static func json(_ status: Int, _ object: String) -> Response {
            Response(status: status, body: Data(object.utf8))
        }
    }

    private let listenFD: Int32
    let port: UInt16
    private let queue = DispatchQueue(label: "gmak8.guestclient.test.http")
    private var source: DispatchSourceRead?
    private let handler: @Sendable (Request) -> Response

    var url: URL { URL(string: "http://127.0.0.1:\(port)")! }

    init(handler: @escaping @Sendable (Request) -> Response) throws {
        self.handler = handler
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        if listen(fd, 16) != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        if nameResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        listenFD = fd
        port = UInt16(bigEndian: bound.sin_port)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        Darwin.close(listenFD)
    }

    private func acceptOnce() {
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let client = withUnsafeMutablePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                accept(listenFD, sockaddrPointer, &length)
            }
        }
        if client < 0 {
            return
        }
        queue.async { [handler] in
            defer { Darwin.close(client) }
            guard let request = readRequest(fd: client) else {
                return
            }
            let response = handler(request)
            let header =
                "HTTP/1.1 \(response.status) OK\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(header.utf8)
            payload.append(response.body)
            payload.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                var offset = 0
                while offset < rawBuffer.count {
                    let written = Darwin.write(client, base + offset, rawBuffer.count - offset)
                    if written <= 0 {
                        return
                    }
                    offset += written
                }
            }
        }
    }
}

private func readRequest(fd: Int32) -> LoopbackHTTPServer.Request? {
    var buffer = Data()
    let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    var chunk = [UInt8](repeating: 0, count: 4096)
    while buffer.range(of: separator) == nil {
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count <= 0 {
            return nil
        }
        buffer.append(contentsOf: chunk.prefix(count))
        if buffer.count > 65_536 {
            return nil
        }
    }
    guard let range = buffer.range(of: separator) else {
        return nil
    }
    let headerText = String(data: buffer[buffer.startIndex..<range.lowerBound], encoding: .utf8) ?? ""
    let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let requestLine = lines.first else {
        return nil
    }
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2 else {
        return nil
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else {
            continue
        }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        headers[name] = value
    }
    var body = Data(buffer[range.upperBound...])
    if let lengthText = headers["content-length"], let length = Int(lengthText) {
        while body.count < length {
            let count = Darwin.read(fd, &chunk, min(chunk.count, length - body.count))
            if count <= 0 {
                return nil
            }
            body.append(contentsOf: chunk.prefix(count))
        }
        body = Data(body.prefix(length))
    }
    return LoopbackHTTPServer.Request(method: String(parts[0]), path: String(parts[1]), body: body)
}

func makeGuestAgentFixture() throws -> (LoopbackHTTPServer, FixtureState) {
    let state = FixtureState()
    let server = try LoopbackHTTPServer { request in
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return .json(200, #"{"ok":true}"#)
        case ("GET", "/disks"):
            if state.mounted {
                return .json(
                    200,
                    #"{"gmak8_data":"mounted","kite_data":"mounted","mountpoint":"/mnt/data","label":"GMAK8_DATA","bytes_total":100,"bytes_free":40}"#
                )
            }
            return .json(
                200,
                #"{"gmak8_data":"unmounted","kite_data":"unmounted","mountpoint":"/mnt/data","label":"","bytes_total":0,"bytes_free":0}"#
            )
        case ("GET", "/kvm"):
            return .json(200, state.kvm ? #"{"kvm":true}"# : #"{"kvm":false}"#)
        case ("GET", "/kubeconfig"):
            if let kubeconfig = state.kubeconfig {
                return LoopbackHTTPServer.Response(status: 200, body: kubeconfig)
            }
            return .json(404, #"{"ok":false,"error":"not found"}"#)
        case ("GET", "/k3s"):
            let minor = state.dataDirMinor
            let minorJSON = minor.isEmpty ? "null" : "\"\(minor)\""
            return .json(
                200,
                """
                {"active":\(state.k3sActive),"version":"v1.33.3+k3s1","data_dir_minor":\(minorJSON),"data_dir_exists":\(state.dataDirExists)}
                """
            )
        case ("POST", "/k3s/start"):
            state.k3sActive = true
            return .json(200, #"{"ok":true}"#)
        case ("GET", "/airgap"):
            if state.airgapPresent {
                return .json(
                    200,
                    #"{"present":true,"files":["gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"],"bytes":\#(state.airgapBytes)}"#
                )
            }
            return .json(200, #"{"present":false,"files":[],"bytes":0}"#)
        case ("PUT", "/airgap/k3s"):
            state.airgapPresent = true
            state.airgapBytes = UInt64(request.body.count)
            state.lastAirgapBody = request.body
            return .json(
                200,
                #"{"present":true,"files":["gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"],"bytes":\#(request.body.count)}"#
            )
        case ("GET", "/node"):
            return .json(200, state.nodeReady ? #"{"ready":true,"name":"gmak8"}"# : #"{"ready":false,"name":"gmak8"}"#)
        case ("PUT", "/time"):
            if request.body.isEmpty {
                return .json(400, #"{"ok":false,"error":"expected unix timestamp or RFC3339"}"#)
            }
            state.lastTimeBody = request.body
            return .json(200, #"{"ok":true}"#)
        case ("POST", "/shutdown"):
            state.shutdowns += 1
            return .json(200, #"{"ok":true}"#)
        default:
            return .json(404, #"{"ok":false,"error":"not found"}"#)
        }
    }
    return (server, state)
}

final class FixtureState: @unchecked Sendable {
    var mounted = true
    var kvm = false
    var shutdowns = 0
    var lastTimeBody = Data()
    var kubeconfig: Data? = Data("apiVersion: v1\nkind: Config\n".utf8)
    var k3sActive = true
    var dataDirMinor = "1.33"
    var dataDirExists = true
    var nodeReady = true
    var airgapPresent = true
    var airgapBytes: UInt64 = 24
    var lastAirgapBody = Data()
}
