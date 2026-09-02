import Darwin
import Foundation

/// Connected unixgram fd plus the local bind path vfkit uses so gvproxy can MSG_PEEK the peer.
public final class VfkitConnection: @unchecked Sendable {
    public let fileHandle: FileHandle
    public let localSocketURL: URL

    public init(fileHandle: FileHandle, localSocketURL: URL) {
        self.fileHandle = fileHandle
        self.localSocketURL = localSocketURL
    }

    public func removeLocalSocket(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: localSocketURL)
    }
}

/// vfkit/Lima handshake: bind a short local unixgram, connect to gvproxy `--listen-vfkit`, send VFKT.
public enum VfkitUnixgram {
    public static let handshakeMagic = Data("VFKT".utf8)
    public static let sendBufferBytes = 1 * 1024 * 1024
    public static let receiveBufferBytes = 4 * 1024 * 1024

    public static func clientSocketURL(nextTo vfkitSocket: URL) -> URL {
        vfkitSocket.deletingLastPathComponent().appending(path: "c.sock")
    }

    public static func connect(
        remote: URL,
        local: URL,
        fileManager: FileManager = .default
    ) throws -> VfkitConnection {
        try UnixgramPath.require(remote)
        try UnixgramPath.require(local)
        let remotePath = UnixgramPath.fileSystemPath(remote)
        let localPath = UnixgramPath.fileSystemPath(local)
        try? fileManager.removeItem(at: local)

        let fd = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw UnixgramPath.posixError("socket", path: localPath)
        }
        var closeOnError = true
        defer {
            if closeOnError {
                Darwin.close(fd)
            }
        }

        var localAddr = try UnixgramPath.sockaddr(path: localPath)
        let bound = withUnsafePointer(to: &localAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if bound != 0 {
            throw UnixgramPath.posixError("bind", path: localPath)
        }

        var remoteAddr = try UnixgramPath.sockaddr(path: remotePath)
        let connected = withUnsafePointer(to: &remoteAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            throw UnixgramPath.posixError("connect", path: remotePath)
        }

        var snd = Int32(sendBufferBytes)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &snd, socklen_t(MemoryLayout<Int32>.size))
        var rcv = Int32(receiveBufferBytes)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcv, socklen_t(MemoryLayout<Int32>.size))

        let written = handshakeMagic.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, handshakeMagic.count)
        }
        if written != handshakeMagic.count {
            throw UnixgramPath.posixError("write VFKT", path: remotePath)
        }

        closeOnError = false
        let fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        return VfkitConnection(fileHandle: fileHandle, localSocketURL: local)
    }
}
