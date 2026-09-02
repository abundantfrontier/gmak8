import Darwin
import Foundation
import Gmak8XPC

enum CLIError: Error, Equatable {
    case engineNotRunning
    case engineError(EngineErrorCode)
    case invalidReply
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            return "gmak8-core is not running (engine.sock is missing)."
        case .engineError(let code):
            return "gmak8-core returned error: \(code.rawValue)."
        case .invalidReply:
            return "gmak8-core returned an invalid reply."
        }
    }
}

enum EngineClient {
    static func status(socketURL: URL, fileManager: FileManager = .default) throws -> EngineStatus {
        let path = socketURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else {
            throw CLIError.engineNotRunning
        }

        let fd = try connect(path: path)
        defer { Darwin.close(fd) }
        try writeAll(fd: fd, data: try NDJSONCodec.encodeLine(EngineRequest.status))
        return try readStatus(fd: fd)
    }
}

private func connect(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw CLIError.engineNotRunning
    }
    var nosigpipe: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    let addr: sockaddr_un
    do {
        addr = try unixAddress(path: path)
    } catch {
        Darwin.close(fd)
        throw CLIError.engineNotRunning
    }
    var address = addr
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if result != 0 {
        Darwin.close(fd)
        throw CLIError.engineNotRunning
    }
    return fd
}

private func unixAddress(path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
    let pathBytes = path.utf8.count
    guard pathBytes + 1 <= maxPath else {
        throw CLIError.engineNotRunning
    }
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
        path.withCString { cString in
            buffer.copyMemory(from: UnsafeRawBufferPointer(start: cString, count: pathBytes + 1))
        }
    }
    return addr
}

private func writeAll(fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return
        }
        var offset = 0
        while offset < rawBuffer.count {
            let written = Darwin.write(fd, base + offset, rawBuffer.count - offset)
            if written <= 0 {
                if errno == EINTR {
                    continue
                }
                throw CLIError.engineNotRunning
            }
            offset += written
        }
    }
}

private func readStatus(fd: Int32) throws -> EngineStatus {
    var buffer = Data()
    while true {
        let line = try readLine(fd: fd, buffer: &buffer)
        if let reply = try? NDJSONCodec.decodeReply(line: line) {
            switch reply {
            case .ok:
                continue
            case .error(let code):
                throw CLIError.engineError(code)
            }
        }
        if let event = try? NDJSONCodec.decodeEvent(line: line), case .status(let status) = event {
            return status
        }
        throw CLIError.invalidReply
    }
}

private func readLine(fd: Int32, buffer: inout Data) throws -> String {
    while true {
        if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            return String(data: Data(lineData), encoding: .utf8) ?? ""
        }
        var chunk = [UInt8](repeating: 0, count: 1024)
        let count = read(fd, &chunk, chunk.count)
        if count < 0 {
            if errno == EINTR {
                continue
            }
            throw CLIError.engineNotRunning
        }
        if count == 0 {
            throw CLIError.invalidReply
        }
        buffer.append(contentsOf: chunk.prefix(count))
    }
}
