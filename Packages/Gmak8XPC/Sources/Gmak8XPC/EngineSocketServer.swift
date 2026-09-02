import Darwin
import Foundation

public enum EngineSocketError: Error, Equatable, Sendable {
    case locked
    case pathTooLong
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
}

public final class EngineSocketServer: @unchecked Sendable {
    public let socketURL: URL
    public let engine: ClusterEngine

    private let peerPolicy: PeerAuthPolicy
    private let identityResolver: any PeerIdentityResolving
    private let daemonIdentity: PeerIdentity
    private let queue = DispatchQueue(label: "dev.gmak8.core.socket")
    private let lock = NSLock()

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    public init(
        socketURL: URL,
        engine: ClusterEngine,
        peerPolicy: PeerAuthPolicy = PeerAuthPolicy(),
        identityResolver: any PeerIdentityResolving = SecCodePeerIdentityResolver(),
        daemonIdentity: PeerIdentity? = nil
    ) throws {
        self.socketURL = socketURL
        self.engine = engine
        self.peerPolicy = peerPolicy
        self.identityResolver = identityResolver
        if let daemonIdentity {
            self.daemonIdentity = daemonIdentity
        } else {
            self.daemonIdentity = try identityResolver.identity(for: getpid())
        }
    }

    public func start() throws {
        try queue.sync {
            try startLocked()
        }
    }

    public func stop() {
        queue.sync {
            stopLocked()
        }
    }

    public func run() throws {
        try start()
        dispatchMain()
    }

    private func startLocked() throws {
        if listenFD >= 0 {
            return
        }

        let path = socketURL.path(percentEncoded: false)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: path) {
            if isSocketLive(path: path) {
                throw EngineErrorCode.locked
            }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw EngineSocketError.socketFailed(errno: errno)
        }
        applySocketFlags(fd)

        var addr = try unixAddress(path: path)
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bindResult != 0 {
            let code = errno
            close(fd)
            throw EngineSocketError.bindFailed(errno: code)
        }

        _ = chmod(path, 0o600)
        _ = fchmod(fd, 0o600)

        if listen(fd, 16) != 0 {
            let code = errno
            close(fd)
            unlink(path)
            throw EngineSocketError.listenFailed(errno: code)
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPending()
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()
    }

    private func stopLocked() {
        lock.lock()
        let openConnections = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        for connection in openConnections {
            connection.close()
        }
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        unlink(socketURL.path(percentEncoded: false))
    }

    private func acceptPending() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else {
            return
        }
        applySocketFlags(client)

        do {
            let pid = try LocalPeerPID.processIdentifier(socketFD: client)
            let peer = try identityResolver.identity(for: pid)
            guard peerPolicy.isAuthorized(peer: peer, daemon: daemonIdentity) else {
                writeReply(fd: client, .error(.unauthorized))
                close(client)
                return
            }
        } catch {
            writeReply(fd: client, .error(.unauthorized))
            close(client)
            return
        }

        let connection = Connection(fd: client, server: self)
        lock.lock()
        connections[client] = connection
        lock.unlock()
        connection.start()
    }

    fileprivate func removeConnection(_ connection: Connection) {
        lock.lock()
        connections[connection.fd] = nil
        lock.unlock()
    }

    private func isSocketLive(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }
        guard var addr = try? unixAddress(path: path) else {
            return false
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }
}

private final class Connection: @unchecked Sendable {
    let fd: Int32
    private weak var server: EngineSocketServer?
    private let queue: DispatchQueue
    private let writeLock = NSLock()
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var subscriberID: UUID?
    private var closed = false

    init(fd: Int32, server: EngineSocketServer) {
        self.fd = fd
        self.server = server
        self.queue = DispatchQueue(label: "dev.gmak8.core.conn.\(fd)")
    }

    func start() {
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

    func close() {
        queue.sync { closeLocked() }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = read(fd, &chunk, chunk.count)
        if count <= 0 {
            closeLocked()
            return
        }
        buffer.append(contentsOf: chunk.prefix(count))
        if buffer.count > 1_048_576 {
            writeReply(.error(.invalidRequest))
            closeLocked()
            return
        }
        drainLines()
    }

    private func drainLines() {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let line = String(data: Data(lineData), encoding: .utf8) else {
                writeReply(.error(.invalidRequest))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            handle(line: trimmed)
        }
    }

    private func handle(line: String) {
        guard let server else {
            return
        }
        switch NDJSONCodec.decodeRequest(line: line) {
        case .failure(let code):
            writeReply(.error(code))
        case .success(let request):
            let reply = server.engine.submit(request)
            writeReply(reply)
            switch request {
            case .status:
                writeEvent(.status(server.engine.currentStatus()))
            case .subscribe:
                if let subscriberID {
                    server.engine.unsubscribe(subscriberID)
                }
                let id = server.engine.subscribe { [weak self] event in
                    guard let self else {
                        return
                    }
                    // Hop so the RPC `{"ok":true}` line is written before stream events.
                    self.queue.async {
                        self.writeEvent(event)
                    }
                }
                subscriberID = id
            default:
                break
            }
        }
    }

    private func writeReply(_ reply: EngineReply) {
        guard let data = try? NDJSONCodec.encodeLine(reply) else {
            return
        }
        writeData(data)
    }

    private func writeEvent(_ event: EngineEvent) {
        guard let data = try? NDJSONCodec.encodeLine(event) else {
            return
        }
        writeData(data)
    }

    private func writeData(_ data: Data) {
        writeLock.lock()
        defer { writeLock.unlock() }
        if closed {
            return
        }
        data.withUnsafeBytes { rawBuffer in
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
                    return
                }
                offset += written
            }
        }
    }

    private func closeLocked() {
        guard !closed else {
            return
        }
        closed = true
        if let subscriberID, let server {
            server.engine.unsubscribe(subscriberID)
        }
        subscriberID = nil
        source?.cancel()
        source = nil
        server?.removeConnection(self)
    }
}

private func writeReply(fd: Int32, _ reply: EngineReply) {
    guard let data = try? NDJSONCodec.encodeLine(reply) else {
        return
    }
    data.withUnsafeBytes { rawBuffer in
        guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return
        }
        _ = Darwin.write(fd, base, rawBuffer.count)
    }
}

private func applySocketFlags(_ fd: Int32) {
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    var nosigpipe: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
}

private func unixAddress(path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    let maxPath = MemoryLayout.size(ofValue: addr.sun_path)
    let pathBytes = path.utf8.count
    guard pathBytes + 1 <= maxPath else {
        throw EngineSocketError.pathTooLong
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
