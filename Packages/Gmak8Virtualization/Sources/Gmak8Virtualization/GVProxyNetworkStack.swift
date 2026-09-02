import Foundation
import Virtualization

/// Starts gvproxy, connects the vfkit unixgram, and exposes 127.0.0.1 ports.
public final class GVProxyNetworkStack: @unchecked Sendable {
    public let executable: URL?
    public let httpSocket: URL
    public let vfkitSocket: URL
    public let clientSocket: URL

    private let mutex = NSLock()
    private var process: GVProxyProcess?
    private var connection: VfkitConnection?

    public init(
        executable: URL?,
        httpSocket: URL,
        vfkitSocket: URL,
        clientSocket: URL? = nil
    ) {
        self.executable = executable
        self.httpSocket = httpSocket
        self.vfkitSocket = vfkitSocket
        self.clientSocket = clientSocket ?? VfkitUnixgram.clientSocketURL(nextTo: vfkitSocket)
    }

    public func preflight(fileManager: FileManager = .default) throws {
        try UnixgramPath.require(httpSocket)
        try UnixgramPath.require(vfkitSocket)
        try UnixgramPath.require(clientSocket)
        guard let executable, fileManager.isExecutableFile(atPath: UnixgramPath.fileSystemPath(executable)) else {
            throw VirtualMachineError.gvproxyMissing(executable)
        }
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
                vfkitSocket: vfkitSocket
            )
        )
        child.onRestarted = { [weak self] in
            try? self?.exposeDefaultPorts()
        }
        mutex.lock()
        process = child
        mutex.unlock()
        try child.start()
        let connected = try VfkitUnixgram.connect(remote: vfkitSocket, local: clientSocket)
        mutex.lock()
        connection = connected
        mutex.unlock()
        return VZFileHandleNetworkDeviceAttachment(fileHandle: connected.fileHandle)
    }

    public func exposeDefaultPorts() throws {
        let client = UnixHTTPClient(socketURL: httpSocket)
        for request in GVProxyExposeRequest.defaultPorts {
            try client.expose(request)
        }
    }

    public func stop() {
        mutex.lock()
        let child = process
        let connected = connection
        process = nil
        connection = nil
        mutex.unlock()
        child?.stop()
        connected?.removeLocalSocket()
        try? FileManager.default.removeItem(at: clientSocket)
    }
}
