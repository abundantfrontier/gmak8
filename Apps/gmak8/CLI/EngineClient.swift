import Darwin
import Foundation
import Gmak8XPC

enum CLIError: Error, Equatable {
    case engineNotRunning
    case communicationFailed
    case engineError(EngineErrorCode, message: String? = nil)
    case invalidReply
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            return "gmak8-core is not running (engine.sock is missing)."
        case .communicationFailed:
            return "could not talk to gmak8-core."
        case .engineError(let code, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "gmak8-core returned error: \(code.rawValue)."
        case .invalidReply:
            return "gmak8-core returned an invalid reply."
        }
    }

    var resetsClusterStatus: Bool {
        switch self {
        case .engineNotRunning, .communicationFailed, .invalidReply:
            return true
        case .engineError:
            return false
        }
    }
}

enum EngineClient {
    static func status(
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 5, tv_usec: 0)
    ) throws -> EngineStatus {
        let fd = try openConnection(socketURL: socketURL, fileManager: fileManager, timeout: timeout)
        defer { Darwin.close(fd) }
        let request = try NDJSONCodec.encodeLine(EngineRequest.status)
        do {
            try writeAll(fd: fd, data: request)
        } catch {
            // Core may already have written unauthorized and closed; drain that reply.
            return try readStatusAfterFailedWrite(fd: fd)
        }
        return try readStatus(fd: fd)
    }

    static func listImages(
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 30, tv_usec: 0)
    ) throws -> NodeImageList {
        try readImageList(request: .imageList, socketURL: socketURL, fileManager: fileManager, timeout: timeout)
    }

    static func pruneImages(
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 30, tv_usec: 0)
    ) throws -> NodeImageList {
        try readImageList(request: .imagePrune, socketURL: socketURL, fileManager: fileManager, timeout: timeout)
    }

    static func portForwardStart(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int,
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 5, tv_usec: 0)
    ) throws -> String {
        let fd = try openConnection(socketURL: socketURL, fileManager: fileManager, timeout: timeout)
        defer { Darwin.close(fd) }
        let data = try NDJSONCodec.encodeLine(
            EngineRequest.portForwardStart(
                kind: kind, namespace: namespace, name: name, local: local, remote: remote)
        )
        do {
            try writeAll(fd: fd, data: data)
        } catch {
            try rethrowFailedWrite(fd: fd)
        }
        switch try readReply(fd: fd) {
        case .started(let id):
            return id
        case .ok:
            throw CLIError.invalidReply
        case .error(let code, let message):
            throw CLIError.engineError(code, message: message)
        }
    }

    static func submit(
        _ request: EngineRequest,
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 5, tv_usec: 0)
    ) throws {
        let fd = try openConnection(socketURL: socketURL, fileManager: fileManager, timeout: timeout)
        defer { Darwin.close(fd) }
        let data = try NDJSONCodec.encodeLine(request)
        do {
            try writeAll(fd: fd, data: data)
        } catch {
            try rethrowFailedWrite(fd: fd)
        }
        switch try readReply(fd: fd) {
        case .ok, .started:
            return
        case .error(let code, let message):
            throw CLIError.engineError(code, message: message)
        }
    }

    static func subscribe(
        socketURL: URL,
        fileManager: FileManager = .default,
        timeout: timeval = timeval(tv_sec: 5, tv_usec: 0),
        onEvent: @escaping @Sendable (EngineEvent) -> Void,
        onError: @escaping @Sendable (CLIError) -> Void
    ) throws -> EngineSubscription {
        let fd = try openConnection(socketURL: socketURL, fileManager: fileManager, timeout: timeout)
        var buffer = Data()
        do {
            try writeAll(fd: fd, data: try NDJSONCodec.encodeLine(EngineRequest.subscribe))
        } catch {
            defer { Darwin.close(fd) }
            try rethrowFailedWrite(fd: fd)
        }
        do {
            switch try readReply(fd: fd, buffer: &buffer) {
            case .ok, .started:
                break
            case .error(let code, let message):
                throw CLIError.engineError(code, message: message)
            }
        } catch let error as CLIError {
            Darwin.close(fd)
            throw mapPostConnect(error)
        } catch {
            Darwin.close(fd)
            throw CLIError.communicationFailed
        }
        clearSocketTimeout(fd: fd)
        return EngineSubscription(fd: fd, leftover: buffer, onEvent: onEvent, onError: onError)
    }
}

final class EngineSubscription: @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "dev.gmak8.engine.subscribe")
    private let onEvent: @Sendable (EngineEvent) -> Void
    private let onError: @Sendable (CLIError) -> Void
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var buffer: Data
    private var closed = false
    private var stoppedContinuation: CheckedContinuation<Void, Never>?

    init(
        fd: Int32,
        leftover: Data,
        onEvent: @escaping @Sendable (EngineEvent) -> Void,
        onError: @escaping @Sendable (CLIError) -> Void
    ) {
        self.fd = fd
        self.buffer = leftover
        self.onEvent = onEvent
        self.onError = onError
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.closeLocked(error: nil)
        }
    }

    func waitUntilStopped() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.lock.lock()
                if self.closed {
                    self.lock.unlock()
                    continuation.resume()
                    return
                }
                self.stoppedContinuation = continuation
                self.lock.unlock()
            }
        }
    }

    private func startLocked() {
        drainLines()
        if closed {
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler { [fd] in
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &chunk, chunk.count)
        if count < 0 {
            if errno == EINTR {
                return
            }
            closeLocked(error: .communicationFailed)
            return
        }
        if count == 0 {
            closeLocked(error: buffer.isEmpty ? .communicationFailed : .invalidReply)
            return
        }
        buffer.append(contentsOf: chunk.prefix(count))
        drainLines()
    }

    private func drainLines() {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            let line = String(data: Data(lineData), encoding: .utf8) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if let reply = try? NDJSONCodec.decodeReply(line: trimmed) {
                if case .error(let code, let message) = reply {
                    closeLocked(error: .engineError(code, message: message))
                    return
                }
                continue
            }
            if let event = try? NDJSONCodec.decodeEvent(line: trimmed) {
                onEvent(event)
                continue
            }
            closeLocked(error: .invalidReply)
            return
        }
    }

    deinit {
        queue.sync {
            closeLocked(error: nil)
        }
    }

    private func closeLocked(error: CLIError?) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let continuation = stoppedContinuation
        stoppedContinuation = nil
        let sourceToCancel = source
        source = nil
        lock.unlock()
        if let error {
            onError(error)
        }
        if let sourceToCancel {
            sourceToCancel.cancel()
        } else {
            Darwin.close(fd)
        }
        continuation?.resume()
    }
}

private func openConnection(socketURL: URL, fileManager: FileManager, timeout: timeval) throws -> Int32 {
    let path = socketURL.path(percentEncoded: false)
    guard fileManager.fileExists(atPath: path) else {
        throw CLIError.engineNotRunning
    }
    return try connect(path: path, timeout: timeout)
}

private func connect(path: String, timeout: timeval) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw CLIError.communicationFailed
    }
    var nosigpipe: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    var receiveTimeout = timeout
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

    let addr: sockaddr_un
    do {
        addr = try unixAddress(path: path)
    } catch {
        Darwin.close(fd)
        throw CLIError.communicationFailed
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
        throw CLIError.communicationFailed
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
                throw CLIError.communicationFailed
            }
            offset += written
        }
    }
}

private func readStatusAfterFailedWrite(fd: Int32) throws -> EngineStatus {
    do {
        return try readStatus(fd: fd)
    } catch let error as CLIError {
        throw mapPostConnect(error)
    }
}

private func rethrowFailedWrite(fd: Int32) throws -> Never {
    do {
        switch try readReply(fd: fd) {
        case .ok, .started:
            throw CLIError.communicationFailed
        case .error(let code, let message):
            throw CLIError.engineError(code, message: message)
        }
    } catch let error as CLIError {
        throw mapPostConnect(error)
    }
}

private func mapPostConnect(_ error: CLIError) -> CLIError {
    switch error {
    case .engineError, .invalidReply:
        return error
    case .engineNotRunning, .communicationFailed:
        return .communicationFailed
    }
}

private func readImageList(
    request: EngineRequest,
    socketURL: URL,
    fileManager: FileManager,
    timeout: timeval
) throws -> NodeImageList {
    let fd = try openConnection(socketURL: socketURL, fileManager: fileManager, timeout: timeout)
    defer { Darwin.close(fd) }
    let encoded = try NDJSONCodec.encodeLine(request)
    do {
        try writeAll(fd: fd, data: encoded)
    } catch {
        try rethrowFailedWrite(fd: fd)
    }
    return try readImages(fd: fd)
}

private func readImages(fd: Int32) throws -> NodeImageList {
    var buffer = Data()
    while true {
        let line = try readLine(fd: fd, buffer: &buffer)
        if let reply = try? NDJSONCodec.decodeReply(line: line) {
            switch reply {
            case .ok, .started:
                continue
            case .error(let code, let message):
                throw CLIError.engineError(code, message: message)
            }
        }
        if let event = try? NDJSONCodec.decodeEvent(line: line), case .images(let list) = event {
            return list
        }
        throw CLIError.invalidReply
    }
}

private func readStatus(fd: Int32) throws -> EngineStatus {
    var buffer = Data()
    while true {
        let line = try readLine(fd: fd, buffer: &buffer)
        if let reply = try? NDJSONCodec.decodeReply(line: line) {
            switch reply {
            case .ok, .started:
                continue
            case .error(let code, let message):
                throw CLIError.engineError(code, message: message)
            }
        }
        if let event = try? NDJSONCodec.decodeEvent(line: line), case .status(let status) = event {
            return status
        }
        throw CLIError.invalidReply
    }
}

private func readReply(fd: Int32, buffer: inout Data) throws -> EngineReply {
    while true {
        let line = try readLine(fd: fd, buffer: &buffer)
        if let reply = try? NDJSONCodec.decodeReply(line: line) {
            return reply
        }
        throw CLIError.invalidReply
    }
}

private func readReply(fd: Int32) throws -> EngineReply {
    var buffer = Data()
    return try readReply(fd: fd, buffer: &buffer)
}

private func clearSocketTimeout(fd: Int32) {
    var timeout = timeval(tv_sec: 0, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
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
            throw CLIError.communicationFailed
        }
        if count == 0 {
            if !buffer.isEmpty {
                throw CLIError.invalidReply
            }
            throw CLIError.communicationFailed
        }
        buffer.append(contentsOf: chunk.prefix(count))
    }
}
