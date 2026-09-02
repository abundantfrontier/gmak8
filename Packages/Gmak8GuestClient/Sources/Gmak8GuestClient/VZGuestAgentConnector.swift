import Foundation
@preconcurrency import Virtualization

public enum VZGuestAgentConnector {
    public static func connect(
        device: VZVirtioSocketDevice,
        queue: DispatchQueue,
        port: UInt32 = Gmak8GuestClient.agentVsockPort
    ) async throws -> VZVirtioSocketChannel {
        let handle = UncheckedVMSocket(device: device, queue: queue)
        return try await withCheckedThrowingContinuation { continuation in
            handle.queue.async {
                handle.device.connect(toPort: port) { result in
                    switch result {
                    case .success(let connection):
                        continuation.resume(returning: VZVirtioSocketChannel(connection: connection))
                    case .failure(let error):
                        continuation.resume(
                            throwing: GuestAgentError.connectFailed(error.localizedDescription)
                        )
                    }
                }
            }
        }
    }

    public static func makeClient(
        device: VZVirtioSocketDevice,
        queue: DispatchQueue,
        port: UInt32 = Gmak8GuestClient.agentVsockPort
    ) -> GuestAgentClient {
        let handle = UncheckedVMSocket(device: device, queue: queue)
        return GuestAgentClient {
            try await connect(device: handle.device, queue: handle.queue, port: port)
        }
    }
}

public final class VZVirtioSocketChannel: GuestByteChannel, @unchecked Sendable {
    private let connection: VZVirtioSocketConnection
    private let inner: FileDescriptorChannel

    public init(connection: VZVirtioSocketConnection) {
        self.connection = connection
        self.inner = FileDescriptorChannel(
            fileDescriptor: connection.fileDescriptor,
            closeFileDescriptor: false
        )
    }

    public func write(_ data: Data) throws {
        try inner.write(data)
    }

    public func read(maxLength: Int) throws -> Data {
        try inner.read(maxLength: maxLength)
    }

    public func close() {
        connection.close()
    }
}

private final class UncheckedVMSocket: @unchecked Sendable {
    let device: VZVirtioSocketDevice
    let queue: DispatchQueue

    init(device: VZVirtioSocketDevice, queue: DispatchQueue) {
        self.device = device
        self.queue = queue
    }
}
