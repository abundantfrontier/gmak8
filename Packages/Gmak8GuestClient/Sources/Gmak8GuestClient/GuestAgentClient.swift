import Foundation

public struct GuestAgentClient: Sendable {
    private let transport: any GuestAgentTransport

    public init(transport: any GuestAgentTransport) {
        self.transport = transport
    }

    public init(baseURL: URL, session: URLSession = .shared) {
        self.transport = URLSessionGuestTransport(baseURL: baseURL, session: session)
    }

    public init(open: @escaping @Sendable () async throws -> any GuestByteChannel) {
        self.transport = StreamGuestTransport(open: open)
    }

    public func health() async throws -> GuestHealth {
        try await send(method: "GET", path: "/health", body: nil, as: GuestHealth.self)
    }

    public func disks() async throws -> GuestDisks {
        try await send(method: "GET", path: "/disks", body: nil, as: GuestDisks.self)
    }

    public func kvm() async throws -> GuestKVM {
        try await send(method: "GET", path: "/kvm", body: nil, as: GuestKVM.self)
    }

    public func setTime(_ time: GuestTime) async throws {
        _ = try await send(method: "PUT", path: "/time", body: try time.encodeBody(), as: GuestOK.self)
    }

    public func shutdown() async throws {
        _ = try await send(method: "POST", path: "/shutdown", body: nil, as: GuestOK.self)
    }

    private func send<T: Decodable>(method: String, path: String, body: Data?, as type: T.Type) async throws -> T {
        let response = try await transport.send(method: method, path: path, body: body)
        if response.statusCode < 200 || response.statusCode >= 300 {
            let message = (try? JSONDecoder().decode(GuestOK.self, from: response.body))?.error
            throw GuestAgentError.httpStatus(response.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw GuestAgentError.decode(String(describing: error))
        }
    }
}
