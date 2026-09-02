import Darwin
import Foundation

/// Exclusive non-blocking flock on sidecar `*.lock` files. The lock files are never unlinked.
public final class DiskFlock: @unchecked Sendable {
    private let mutex = NSLock()
    private var fds: [Int32] = []

    public init() {}

    public var isHolding: Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return !fds.isEmpty
    }

    public func acquire(urls: [URL]) throws {
        mutex.lock()
        defer { mutex.unlock() }
        if !fds.isEmpty {
            return
        }
        var acquired: [Int32] = []
        do {
            for url in urls {
                try acquired.append(Self.openAndLock(url: url))
            }
        } catch {
            Self.unlockAndClose(acquired)
            throw error
        }
        fds = acquired
    }

    public func release() {
        mutex.lock()
        defer { mutex.unlock() }
        Self.unlockAndClose(fds)
        fds.removeAll()
    }

    deinit {
        Self.unlockAndClose(fds)
    }

    private static func openAndLock(url: URL) throws -> Int32 {
        let path = url.path(percentEncoded: false)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            throw VirtualMachineError.posix(errno: errno, path: path)
        }
        applyCloseOnExec(fd)
        if fchmod(fd, 0o600) != 0 {
            let code = errno
            Darwin.close(fd)
            throw VirtualMachineError.posix(errno: code, path: path)
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK || code == EAGAIN {
                throw VirtualMachineError.diskImagesLocked
            }
            throw VirtualMachineError.posix(errno: code, path: path)
        }
        return fd
    }

    private static func unlockAndClose(_ fds: [Int32]) {
        for fd in fds {
            _ = flock(fd, LOCK_UN)
            Darwin.close(fd)
        }
    }
}

private func applyCloseOnExec(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFD)
    if flags >= 0 {
        _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
    }
}
