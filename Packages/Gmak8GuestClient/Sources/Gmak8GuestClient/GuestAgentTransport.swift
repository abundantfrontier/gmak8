import Foundation

public struct GuestHTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol GuestAgentTransport: Sendable {
    func send(method: String, path: String, body: Data?) async throws -> GuestHTTPResponse
}

public struct StreamGuestTransport: GuestAgentTransport {
    private let open: @Sendable () async throws -> any GuestByteChannel

    public init(open: @escaping @Sendable () async throws -> any GuestByteChannel) {
        self.open = open
    }

    public func send(method: String, path: String, body: Data?) async throws -> GuestHTTPResponse {
        let channel = try await open()
        defer { channel.close() }
        try channel.write(encodeHTTPRequest(method: method, path: path, body: body))
        return try readHTTPResponse(from: channel)
    }
}

public struct URLSessionGuestTransport: GuestAgentTransport, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func send(method: String, path: String, body: Data?) async throws -> GuestHTTPResponse {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var request = URLRequest(url: baseURL.appending(path: trimmed))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return GuestHTTPResponse(statusCode: status, body: data)
    }
}

func encodeHTTPRequest(method: String, path: String, body: Data?) -> Data {
    var header = "\(method) \(path) HTTP/1.1\r\n"
    header += "Host: gmak8-agent\r\n"
    header += "User-Agent: gmak8-guest-client\r\n"
    header += "Accept: application/json\r\n"
    header += "Connection: close\r\n"
    if let body {
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(body.count)\r\n"
    }
    header += "\r\n"
    var data = Data(header.utf8)
    if let body {
        data.append(body)
    }
    return data
}

func readHTTPResponse(from channel: any GuestByteChannel) throws -> GuestHTTPResponse {
    var buffer = Data()
    let headerSeparator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    while true {
        if let range = buffer.range(of: headerSeparator) {
            let headerData = buffer[buffer.startIndex..<range.lowerBound]
            var body = Data(buffer[range.upperBound...])
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                throw GuestAgentError.io("invalid HTTP headers")
            }
            let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
            guard let statusLine = lines.first else {
                throw GuestAgentError.io("missing status line")
            }
            let statusCode = parseStatusCode(statusLine)
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else {
                    continue
                }
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
            if let lengthText = headers["content-length"], let length = Int(lengthText) {
                while body.count < length {
                    let chunk = try channel.read(maxLength: length - body.count)
                    if chunk.isEmpty {
                        throw GuestAgentError.io("eof before content-length")
                    }
                    body.append(chunk)
                }
                body = body.prefix(length)
            } else {
                while true {
                    let chunk = try channel.read(maxLength: 4096)
                    if chunk.isEmpty {
                        break
                    }
                    body.append(chunk)
                }
            }
            return GuestHTTPResponse(statusCode: statusCode, body: body)
        }
        let chunk = try channel.read(maxLength: 4096)
        if chunk.isEmpty {
            throw GuestAgentError.io("eof before headers")
        }
        buffer.append(chunk)
        if buffer.count > 65_536 {
            throw GuestAgentError.io("headers too large")
        }
    }
}

func parseStatusCode(_ statusLine: Substring) -> Int {
    let parts = statusLine.split(separator: " ")
    if parts.count >= 2, let code = Int(parts[1]) {
        return code
    }
    return 0
}
