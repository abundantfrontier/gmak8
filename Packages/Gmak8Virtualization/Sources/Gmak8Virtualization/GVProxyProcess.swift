import Foundation

/// Supervises the gvproxy helper. Restarts on crash with backoff.
///
/// unixgram ENOBUFS under large overlay pulls is a known gvproxy/vfkit exit.
/// Restart re-exposes the port table; the VZ file-handle NIC stays bound to the
/// old datagram fd, so datapath recovery may still need a VM restart.
public final class GVProxyProcess: @unchecked Sendable {
    public static let datapathMayBeDeadMessage =
        "gvproxy restarted; guest overlay datapath may be dead until the VM is restarted (unixgram ENOBUFS)"

    public struct Config: Sendable {
        public var executable: URL
        public var httpSocket: URL
        public var vfkitSocket: URL
        public var mtu: Int
        public var readyTimeout: TimeInterval
        public var maximumRestarts: Int?
        public var logFile: URL?
        public var backoff: @Sendable (Int) -> TimeInterval

        public init(
            executable: URL,
            httpSocket: URL,
            vfkitSocket: URL,
            mtu: Int = GuestNetwork.mtu,
            readyTimeout: TimeInterval = 10,
            maximumRestarts: Int? = nil,
            logFile: URL? = nil,
            backoff: @escaping @Sendable (Int) -> TimeInterval = GVProxyProcess.restartBackoff
        ) {
            self.executable = executable
            self.httpSocket = httpSocket
            self.vfkitSocket = vfkitSocket
            self.mtu = mtu
            self.readyTimeout = readyTimeout
            self.maximumRestarts = maximumRestarts
            self.logFile = logFile
            self.backoff = backoff
        }
    }

    public static func restartBackoff(attempt: Int) -> TimeInterval {
        min(30.0, pow(2.0, Double(max(attempt, 1) - 1)))
    }

    public let config: Config
    public var onRestarted: (@Sendable () -> Void)?

    private let condition = NSCondition()
    private let supervisorQueue = DispatchQueue(label: "dev.gmak8.gvproxy")
    private var process: Process?
    private var logHandle: FileHandle?
    private var stopRequested = false
    private var restartGeneration: UInt64 = 0
    private var restartAttempt = 0
    public private(set) var restartCount = 0

    public init(config: Config) {
        self.config = config
    }

    public var isRunning: Bool {
        condition.lock()
        defer { condition.unlock() }
        return process?.isRunning == true
    }

    public func start() throws {
        condition.lock()
        stopRequested = false
        condition.unlock()
        do {
            try launchLocked()
            try waitUntilSocketsExist()
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        condition.lock()
        stopRequested = true
        restartGeneration += 1
        let running = process
        process = nil
        condition.broadcast()
        condition.unlock()
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
        let log = try openLogFile()
        child.standardError = log ?? FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            self?.handleExit()
        }

        condition.lock()
        if stopRequested {
            condition.unlock()
            throw VirtualMachineError.stoppedDuringStart
        }
        logHandle = log
        process = child
        do {
            try child.run()
        } catch {
            process = nil
            logHandle = nil
            condition.unlock()
            throw VirtualMachineError.networkFailed(
                "failed to launch gvproxy: \(error.localizedDescription)"
            )
        }
        if stopRequested {
            let running = process
            process = nil
            condition.unlock()
            running?.terminate()
            running?.waitUntilExit()
            throw VirtualMachineError.stoppedDuringStart
        }
        condition.unlock()
    }

    private func waitUntilSocketsExist() throws {
        let deadline = Date().addingTimeInterval(config.readyTimeout)
        let httpPath = UnixgramPath.fileSystemPath(config.httpSocket)
        let vfkitPath = UnixgramPath.fileSystemPath(config.vfkitSocket)
        while true {
            condition.lock()
            let stopping = stopRequested
            let running = process?.isRunning == true
            condition.unlock()
            if stopping {
                throw VirtualMachineError.stoppedDuringStart
            }
            if !running {
                throw VirtualMachineError.networkFailed("gvproxy exited during start")
            }
            if FileManager.default.fileExists(atPath: httpPath)
                && FileManager.default.fileExists(atPath: vfkitPath)
            {
                return
            }
            if Date() >= deadline {
                throw VirtualMachineError.networkFailed(
                    "gvproxy sockets did not appear within \(config.readyTimeout)s"
                )
            }
            condition.lock()
            if stopRequested {
                condition.unlock()
                throw VirtualMachineError.stoppedDuringStart
            }
            let slice = min(0.05, deadline.timeIntervalSinceNow)
            if slice > 0 {
                _ = condition.wait(until: Date().addingTimeInterval(slice))
            }
            condition.unlock()
        }
    }

    private func handleExit() {
        condition.lock()
        if stopRequested {
            process = nil
            condition.unlock()
            return
        }
        process = nil
        let attempt = restartAttempt + 1
        let cap = config.maximumRestarts
        let generation = restartGeneration
        condition.unlock()
        if let cap, attempt > cap {
            return
        }
        let delay = config.backoff(attempt)
        supervisorQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            self.condition.lock()
            let cancelled = self.stopRequested || self.restartGeneration != generation
            self.condition.unlock()
            if cancelled {
                return
            }
            do {
                try self.launchLocked()
                try self.waitUntilSocketsExist()
                self.condition.lock()
                if self.stopRequested || self.restartGeneration != generation {
                    let running = self.process
                    self.process = nil
                    self.condition.unlock()
                    running?.terminate()
                    running?.waitUntilExit()
                    return
                }
                self.restartAttempt = attempt
                self.restartCount += 1
                self.condition.unlock()
                self.appendLogLine(Self.datapathMayBeDeadMessage)
                self.onRestarted?()
            } catch {
                self.condition.lock()
                self.restartAttempt = attempt
                let stopping = self.stopRequested
                self.condition.unlock()
                if !stopping {
                    self.handleExit()
                }
            }
        }
    }

    private func openLogFile() throws -> FileHandle? {
        guard let url = config.logFile else {
            return nil
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let path = UnixgramPath.fileSystemPath(url)
        if fileManager.fileExists(atPath: path) {
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value ?? 0
            if size > 5 * 1024 * 1024 {
                let rotated = url.appendingPathExtension("1")
                try? fileManager.removeItem(at: rotated)
                try? fileManager.moveItem(at: url, to: rotated)
            }
        }
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        return handle
    }

    private func appendLogLine(_ line: String) {
        guard let handle = logHandle, let data = (line + "\n").data(using: .utf8) else {
            return
        }
        handle.write(data)
    }

    private func unlinkSockets() {
        try? FileManager.default.removeItem(at: config.httpSocket)
        try? FileManager.default.removeItem(at: config.vfkitSocket)
    }
}
