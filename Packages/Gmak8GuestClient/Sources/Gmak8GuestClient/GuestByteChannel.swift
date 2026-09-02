import Darwin
import Foundation

public protocol GuestByteChannel: Sendable {
    func write(_ data: Data) throws
    func read(maxLength: Int) throws -> Data
    func close()
}

public protocol GuestIOTimeoutAdjusting: AnyObject {
    func setIOTimeout(seconds: Int)
}

public final class FileDescriptorChannel: GuestByteChannel, GuestIOTimeoutAdjusting, @unchecked Sendable {
    private let fd: Int32
    private let onClose: @Sendable () -> Void
    private let lock = NSLock()
    private var closed = false

    public init(fileDescriptor: Int32, closeFileDescriptor: Bool) {
        self.fd = fileDescriptor
        if closeFileDescriptor {
            self.onClose = { Darwin.close(fileDescriptor) }
        } else {
            self.onClose = {}
        }
        Self.applyIOTimeout(fileDescriptor)
    }

    public init(fileDescriptor: Int32, onClose: @escaping @Sendable () -> Void) {
        self.fd = fileDescriptor
        self.onClose = onClose
        Self.applyIOTimeout(fileDescriptor)
    }

    private static let ioTimeoutSeconds: Int = 5

    private static func applyIOTimeout(_ fd: Int32) {
        applyIOTimeout(fd, seconds: ioTimeoutSeconds)
    }

    private static func applyIOTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    public func setIOTimeout(seconds: Int) {
        Self.applyIOTimeout(fd, seconds: seconds)
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(fd, base + offset, rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        throw GuestAgentError.io("write timeout")
                    }
                    throw GuestAgentError.io("write errno \(errno)")
                }
                if written == 0 {
                    throw GuestAgentError.io("write eof")
                }
                offset += written
            }
        }
    }

    public func read(maxLength: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        while true {
            let count = Darwin.read(fd, &buffer, maxLength)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw GuestAgentError.io("read timeout")
                }
                throw GuestAgentError.io("read errno \(errno)")
            }
            if count == 0 {
                return Data()
            }
            return Data(buffer.prefix(count))
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if closed {
            return
        }
        closed = true
        onClose()
    }

    deinit {
        close()
    }
}

enum TCPGuestChannel {
    static func connect(host: String, port: UInt16) throws -> FileDescriptorChannel {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw GuestAgentError.connectFailed("socket errno \(errno)")
        }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let pton = host.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        if pton != 1 {
            Darwin.close(fd)
            throw GuestAgentError.connectFailed("inet_pton \(host)")
        }
        let result = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            let code = errno
            Darwin.close(fd)
            throw GuestAgentError.connectFailed("connect errno \(code)")
        }
        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        return FileDescriptorChannel(fileDescriptor: fd, closeFileDescriptor: true)
    }
}
