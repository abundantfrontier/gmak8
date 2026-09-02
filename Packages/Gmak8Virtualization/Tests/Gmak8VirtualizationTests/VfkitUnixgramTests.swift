import Darwin
import Foundation
import Testing

@testable import Gmak8Virtualization

struct VfkitUnixgramTests {
    @Test func connectSendsVfkitMagicToUnixgramPeer() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = root.appending(path: "n.sock")
        let local = root.appending(path: "c.sock")
        try UnixgramPath.require(remote)
        try UnixgramPath.require(local)

        let listenFD = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        try #require(listenFD >= 0)
        defer { Darwin.close(listenFD) }

        var addr = try UnixgramPath.sockaddr(path: UnixgramPath.fileSystemPath(remote))
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(listenFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0)

        let connection = try VfkitUnixgram.connect(remote: remote, local: local)
        defer { connection.removeLocalSocket() }

        var buffer = [UInt8](repeating: 0, count: 16)
        let n = Darwin.read(listenFD, &buffer, buffer.count)
        try #require(n == VfkitUnixgram.handshakeMagic.count)
        #expect(Data(buffer.prefix(Int(n))) == VfkitUnixgram.handshakeMagic)
        #expect(FileManager.default.fileExists(atPath: UnixgramPath.fileSystemPath(local)))
    }

    @Test func clientSocketSitsNextToVfkitSocket() {
        let vfkit = URL(fileURLWithPath: "/tmp/n.sock")
        #expect(VfkitUnixgram.clientSocketURL(nextTo: vfkit).lastPathComponent == "c.sock")
    }
}
