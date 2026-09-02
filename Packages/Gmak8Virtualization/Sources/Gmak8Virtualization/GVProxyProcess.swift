import Foundation

/// Supervises the gvproxy helper. Restarts on crash with backoff.
///
/// unixgram ENOBUFS under large overlay pulls is a known gvproxy/vfkit exit.
/// Restart re-exposes the port table; the VZ file-handle NIC stays bound to the
/// old datagram fd, so datapath recovery may still need a VM restart.
public final class GVProxyProcess: @unchecked Sendable {
    public struct Config: Sendable {
        public var executable: URL
        public var httpSocket: URL
        public var vfkitSocket: URL
        public var mtu: Int
        public var readyTimeout: TimeInterval
        public var maximumRestarts: Int?
        public var backoff: @Sendable (Int) -> TimeInterval

        public init(
            executable: URL,
            httpSocket: URL,
            vfkitSocket: URL,
            mtu: Int = GuestNetwork.mtu,
            readyTimeout: TimeInterval = 10,
            maximumRestarts: Int? = nil,
            backoff: @escaping @Sendable (Int) -> TimeInterval = GVProxyProcess.restartBackoff
        ) {
            self.executable = executable
            self.httpSocket = httpSocket
            self.vfkitSocket = vfkitSocket
            self.mtu = mtu
            self.readyTimeout = readyTimeout
            self.maximumRestarts = maximumRestarts
            self.backoff = backoff
        }
    }

    public static func restartBackoff(attempt: Int) -> TimeInterval {
        min(30.0, pow(2.0, Double(max(attempt, 1) - 1)))
    }

    public let config: Config
    public var onRestarted: (@Sendable () -> Void)?

    private let mutex = NSLock()
    private let supervisorQueue = DispatchQueue(label: "dev.gmak8.gvproxy")
    private var process: Process?
    private var stopRequested = false
    private var restartAttempt = 0
    public private(set) var restartCount = 0

    public init(config: Config) {
        self.config = config
    }

    public var isRunning: Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return process?.isRunning == true
    }

    public func start() throws {
        mutex.lock()
        stopRequested = false
        mutex.unlock()
        try launchLocked()
        try waitUntilSocketsExist()
    }

    public func stop() {
        mutex.lock()
        stopRequested = true
        let running = process
        process = nil
        mutex.unlock()
        running?.terminate()
        running?.waitUntilExit()
        unlinkSockets()
    }

    private func launchLocked() throws {
        try UnixgramPath.require(config.httpSocket)
        try UnixgramPath.require(config.vfkitSocket)
        unlinkSockets()
        try FileManager.default.createDirectory(
            at: config.httpSocket.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let args = try GVProxyLaunch.arguments(
            httpSocket: config.httpSocket,
            vfkitSocket: config.vfkitSocket,
            mtu: config.mtu
        )
        let child = Process()
        child.executableURL = config.executable
        child.arguments = args
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            self?.handleExit()
        }

        mutex.lock()
        process = child
        mutex.unlock()
        do {
            try child.run()
        } catch {
            mutex.lock()
            process = nil
            mutex.unlock()
            throw VirtualMachineError.networkFailed(
                "failed to launch gvproxy: \(error.localizedDescription)"
            )
        }
    }

    private func waitUntilSocketsExist() throws {
        let deadline = Date().addingTimeInterval(config.readyTimeout)
        let httpPath = UnixgramPath.fileSystemPath(config.httpSocket)
        let vfkitPath = UnixgramPath.fileSystemPath(config.vfkitSocket)
        while Date() < deadline {
            if isStopRequested() {
                throw VirtualMachineError.stoppedDuringStart
            }
            if !isRunning {
                throw VirtualMachineError.networkFailed("gvproxy exited during start")
            }
            if FileManager.default.fileExists(atPath: httpPath)
                && FileManager.default.fileExists(atPath: vfkitPath)
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw VirtualMachineError.networkFailed("gvproxy sockets did not appear within \(config.readyTimeout)s")
    }

    private func handleExit() {
        mutex.lock()
        let stopping = stopRequested
        process = nil
        let attempt = restartAttempt + 1
        let cap = config.maximumRestarts
        mutex.unlock()
        if stopping {
            return
        }
        if let cap, attempt > cap {
            return
        }
        let delay = config.backoff(attempt)
        supervisorQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            if self.isStopRequested() {
                return
            }
            do {
                try self.launchLocked()
                try self.waitUntilSocketsExist()
                self.mutex.lock()
                self.restartAttempt = attempt
                self.restartCount += 1
                self.mutex.unlock()
                self.onRestarted?()
            } catch {
                self.mutex.lock()
                self.restartAttempt = attempt
                self.mutex.unlock()
                self.handleExit()
            }
        }
    }

    private func isStopRequested() -> Bool {
        mutex.lock()
        defer { mutex.unlock() }
        return stopRequested
    }

    private func unlinkSockets() {
        try? FileManager.default.removeItem(at: config.httpSocket)
        try? FileManager.default.removeItem(at: config.vfkitSocket)
    }
}
