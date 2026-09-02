import Foundation

/// gvproxy `POST /services/forwarder/expose` body. `local` is always 127.0.0.1, never 0.0.0.0.
public struct GVProxyExposeRequest: Equatable, Sendable, Codable {
    public let local: String
    public let remote: String

    public init(local: String, remote: String) throws {
        try Self.validate(local: local, remote: remote)
        self.local = local
        self.remote = remote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let local = try container.decode(String.self, forKey: .local)
        let remote = try container.decode(String.self, forKey: .remote)
        try self.init(local: local, remote: remote)
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

    public static func isAlreadyBoundError(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Bind failures contain "already in use"; those must fall through to 16443.
        if lower.contains("address already in use") || lower.contains("bind:") {
            return false
        }
        return lower.contains("already exist")
            || lower.contains("already running")
            || lower.contains("already exposed")
            || lower.contains("already bound")
    }

    public static func validate(local: String, remote: String) throws {
        guard let host = Self.host(in: local), let port = Self.port(in: local) else {
            throw VirtualMachineError.networkFailed("invalid expose local address: \(local)")
        }
        if host == GuestNetwork.anyAddress {
            throw VirtualMachineError.networkFailed("expose must not use \(GuestNetwork.anyAddress)")
        }
        if host != GuestNetwork.hostLoopback {
            throw VirtualMachineError.networkFailed(
                "expose local host must be \(GuestNetwork.hostLoopback), got \(host)")
        }
        if GuestNetwork.forbiddenHostPorts.contains(port) {
            throw VirtualMachineError.networkFailed("refuse host port \(port)")
        }
        guard let remoteHost = Self.host(in: remote), Self.port(in: remote) != nil else {
            throw VirtualMachineError.networkFailed("invalid expose remote address: \(remote)")
        }
        if remoteHost == GuestNetwork.anyAddress {
            throw VirtualMachineError.networkFailed("expose must not use \(GuestNetwork.anyAddress)")
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
