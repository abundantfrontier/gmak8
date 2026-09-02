import Darwin
import Foundation

public enum SparseDiskImage {
    public static func createIfMissing(at url: URL, size: UInt64, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = url.path(percentEncoded: false)
        if fileManager.fileExists(atPath: path) {
            try enforceOwnerReadWrite(path: path)
            return
        }
        try createSparseFile(path: path, size: size)
    }

    public static func createEmptyIfMissing(at url: URL, fileManager: FileManager = .default) throws {
        try createIfMissing(at: url, size: 0, fileManager: fileManager)
    }

    private static func createSparseFile(path: String, size: UInt64) throws {
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw VirtualMachineError.posix(errno: errno, path: path)
        }
        defer { Darwin.close(fd) }
        if fchmod(fd, 0o600) != 0 {
            throw VirtualMachineError.posix(errno: errno, path: path)
        }
        if ftruncate(fd, off_t(size)) != 0 {
            throw VirtualMachineError.posix(errno: errno, path: path)
        }
    }

    private static func enforceOwnerReadWrite(path: String) throws {
        if chmod(path, 0o600) != 0 {
            throw VirtualMachineError.posix(errno: errno, path: path)
        }
    }
}
