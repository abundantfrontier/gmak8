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
    func sendFile(
        method: String,
        path: String,
        fileURL: URL,
        contentType: String,
        extraHeaders: [String: String],
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestHTTPResponse
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

    public func sendFile(
        method: String,
        path: String,
        fileURL: URL,
        contentType: String,
        extraHeaders: [String: String],
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestHTTPResponse {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let channel = try await open()
        do {
            return try await withTaskCancellationHandler {
                defer { channel.close() }
                if let adjustable = channel as? any GuestIOTimeoutAdjusting {
                    adjustable.setIOTimeout(seconds: 5)
                }
                var headers = extraHeaders
                headers["Content-Type"] = contentType
                headers["Content-Length"] = String(size)
                try channel.write(encodeHTTPHeaders(method: method, path: path, extraHeaders: headers))
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }
                var sent: Int64 = 0
                onProgress?(0, size)
                while true {
                    try Task.checkCancellation()
                    let chunk = try handle.read(upToCount: 64 * 1_024) ?? Data()
                    if chunk.isEmpty {
                        break
                    }
                    try channel.write(chunk)
                    sent += Int64(chunk.count)
                    onProgress?(sent, size)
                }
                if let adjustable = channel as? any GuestIOTimeoutAdjusting {
                    adjustable.setIOTimeout(seconds: 120)
                }
                try Task.checkCancellation()
                return try readHTTPResponse(from: channel)
            } onCancel: {
                channel.close()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw error
        }
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
        var request = URLRequest(url: url(for: path))
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

    public func sendFile(
        method: String,
        path: String,
        fileURL: URL,
        contentType: String,
        extraHeaders: [String: String],
        onProgress: (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> GuestHTTPResponse {
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        onProgress?(0, size)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw error
        }
        onProgress?(size, size)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return GuestHTTPResponse(statusCode: status, body: data)
    }

    private func url(for path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appending(path: trimmed)
    }
}

func encodeHTTPHeaders(method: String, path: String, extraHeaders: [String: String] = [:]) -> Data {
    var header = "\(method) \(path) HTTP/1.1\r\n"
    header += "Host: gmak8-agent\r\n"
    header += "User-Agent: gmak8-guest-client\r\n"
    header += "Accept: application/json\r\n"
    header += "Connection: close\r\n"
    var seen: Set<String> = ["host", "user-agent", "accept", "connection"]
    for (name, value) in extraHeaders {
        let key = name.lowercased()
        if seen.contains(key) {
            continue
        }
        seen.insert(key)
        header += "\(name): \(value)\r\n"
    }
    header += "\r\n"
    return Data(header.utf8)
}

func encodeHTTPRequest(method: String, path: String, body: Data?) -> Data {
    var extra: [String: String] = [:]
    if let body {
        extra["Content-Type"] = "application/json"
        extra["Content-Length"] = String(body.count)
    }
    var data = encodeHTTPHeaders(method: method, path: path, extraHeaders: extra)
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
