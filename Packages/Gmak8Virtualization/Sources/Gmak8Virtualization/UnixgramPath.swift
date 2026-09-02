import Darwin
import Foundation

/// Darwin `sockaddr_un.sun_path` is 104 bytes including the trailing NUL.
public enum UnixgramPath {
    public static let sunPathByteCount = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    public static func fits(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else {
                return false
            }
            return strlen(pointer) + 1 <= sunPathByteCount
        }
    }

    public static func require(_ url: URL) throws {
        if !fits(url) {
            throw VirtualMachineError.socketPathTooLong(url)
        }
    }

    public static func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    static func sockaddr(path: String) throws -> sockaddr_un {
        try require(URL(fileURLWithPath: path))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (index, byte) in bytes.enumerated() {
                raw[index] = UInt8(bitPattern: byte)
            }
        }
        let prefix = MemoryLayout.size(ofValue: addr.sun_len) + MemoryLayout.size(ofValue: addr.sun_family)
        addr.sun_len = UInt8(prefix + bytes.count)
        return addr
    }

    static func posixError(_ operation: String, path: String) -> VirtualMachineError {
        let message = String(cString: strerror(errno))
        return .networkFailed("\(operation) \(path): \(message) (\(errno))")
    }
}
