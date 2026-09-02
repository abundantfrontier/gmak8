import Foundation

/// gvproxy `POST /services/forwarder/expose` body. `local` is always 127.0.0.1, never 0.0.0.0.
public struct GVProxyExposeRequest: Equatable, Sendable, Codable {
    public var local: String
    public var remote: String

    public init(local: String, remote: String) throws {
        try Self.validate(local: local, remote: remote)
        self.local = local
        self.remote = remote
    }

    public init(hostPort: Int, guestPort: Int) throws {
        try self.init(
            local: "\(GuestNetwork.hostLoopback):\(hostPort)",
            remote: "\(GuestNetwork.guestIPv4):\(guestPort)"
        )
    }

    public var localPort: Int? {
        Self.port(in: local)
    }

    public func jsonUTF8() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static let defaultPorts: [GVProxyExposeRequest] = {
        // Constants are pinned in GuestNetwork; validation cannot fail.
        try! [
            GVProxyExposeRequest(hostPort: GuestNetwork.apiHostPort, guestPort: GuestNetwork.apiGuestPort),
            GVProxyExposeRequest(hostPort: GuestNetwork.httpHostPort, guestPort: GuestNetwork.httpGuestPort),
            GVProxyExposeRequest(hostPort: GuestNetwork.httpsHostPort, guestPort: GuestNetwork.httpsGuestPort),
        ]
    }()

    public static func validate(local: String, remote: String) throws {
        if local.contains(GuestNetwork.anyAddress) || remote.contains(GuestNetwork.anyAddress) {
            throw VirtualMachineError.networkFailed("expose must not use \(GuestNetwork.anyAddress)")
        }
        guard let host = Self.host(in: local), let port = Self.port(in: local) else {
            throw VirtualMachineError.networkFailed("invalid expose local address: \(local)")
        }
        if host != GuestNetwork.hostLoopback {
            throw VirtualMachineError.networkFailed(
                "expose local host must be \(GuestNetwork.hostLoopback), got \(host)")
        }
        if GuestNetwork.forbiddenHostPorts.contains(port) {
            throw VirtualMachineError.networkFailed("refuse host port \(port)")
        }
        if Self.port(in: remote) == nil {
            throw VirtualMachineError.networkFailed("invalid expose remote address: \(remote)")
        }
    }

    private static func host(in endpoint: String) -> String? {
        let parts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }
        return String(parts[0])
    }

    private static func port(in endpoint: String) -> Int? {
        let parts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]), (1...65_535).contains(port) else {
            return nil
        }
        return port
    }
}
