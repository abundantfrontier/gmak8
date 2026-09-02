import Foundation
import Virtualization

/// Starts gvproxy, connects the vfkit unixgram, and exposes 127.0.0.1 ports.
public final class GVProxyNetworkStack: @unchecked Sendable {
    public let executable: URL?
    public let httpSocket: URL
    public let vfkitSocket: URL
    public let clientSocket: URL
    public let logFile: URL?

    public var onDegraded: (@Sendable (String) -> Void)?

    private let mutex = NSLock()
    private var process: GVProxyProcess?
    private var connection: VfkitConnection?
    private var initialExposeCompleted = false

    public init(
        executable: URL?,
        httpSocket: URL,
        vfkitSocket: URL,
        clientSocket: URL? = nil,
        logFile: URL? = nil
    ) {
        self.executable = executable
        self.httpSocket = httpSocket
        self.vfkitSocket = vfkitSocket
        self.clientSocket = clientSocket ?? VfkitUnixgram.clientSocketURL(nextTo: vfkitSocket)
        self.logFile = logFile
    }

    public func preflight(fileManager: FileManager = .default) throws {
        try UnixgramPath.require(httpSocket)
        try UnixgramPath.require(vfkitSocket)
        try UnixgramPath.require(clientSocket)
        guard let executable, fileManager.isExecutableFile(atPath: UnixgramPath.fileSystemPath(executable)) else {
            throw VirtualMachineError.gvproxyMissing(executable)
        }
    }

    public func cancel() {
        mutex.lock()
        let child = process
        mutex.unlock()
        child?.stop()
    }

    public func start() throws -> VZFileHandleNetworkDeviceAttachment {
        try preflight()
        guard let executable else {
            throw VirtualMachineError.gvproxyMissing(nil)
        }
        let child = GVProxyProcess(
            config: GVProxyProcess.Config(
                executable: executable,
                httpSocket: httpSocket,
                vfkitSocket: vfkitSocket,
                logFile: logFile
            )
        )
        child.onRestarted = { [weak self] in
            self?.handleHelperRestart()
        }
        mutex.lock()
        process = child
        initialExposeCompleted = false
        mutex.unlock()
        do {
            try child.start()
            let connected = try VfkitUnixgram.connect(remote: vfkitSocket, local: clientSocket)
            mutex.lock()
            connection = connected
            mutex.unlock()
            return VZFileHandleNetworkDeviceAttachment(fileHandle: connected.fileHandle)
        } catch {
            child.stop()
            mutex.lock()
            process = nil
            connection = nil
            mutex.unlock()
            throw error
        }
    }

    public func exposeDefaultPorts() throws {
        let client = UnixHTTPClient(socketURL: httpSocket)
        for request in GVProxyExposeRequest.defaultPorts {
            try client.expose(request)
        }
        mutex.lock()
        initialExposeCompleted = true
        mutex.unlock()
    }

    public func stop() {
        mutex.lock()
        let child = process
        let connected = connection
        process = nil
        connection = nil
        initialExposeCompleted = false
        mutex.unlock()
        child?.stop()
        connected?.removeLocalSocket()
        try? FileManager.default.removeItem(at: clientSocket)
    }

    private func handleHelperRestart() {
        mutex.lock()
        let shouldExpose = initialExposeCompleted
        mutex.unlock()
        var message = GVProxyProcess.datapathMayBeDeadMessage
        if shouldExpose {
            do {
                try exposeDefaultPorts()
            } catch {
                message += "; re-expose failed: \(error.localizedDescription)"
            }
        }
        onDegraded?(message)
    }
}
