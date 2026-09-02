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

    public func kubeconfig() async throws -> Data {
        let response = try await transport.send(method: "GET", path: "/kubeconfig", body: nil)
        if response.statusCode < 200 || response.statusCode >= 300 {
            let message = (try? JSONDecoder().decode(GuestOK.self, from: response.body))?.error
            throw GuestAgentError.httpStatus(response.statusCode, message)
        }
        return response.body
    }

    public func k3s() async throws -> GuestK3s {
        try await send(method: "GET", path: "/k3s", body: nil, as: GuestK3s.self)
    }

    public func startK3s() async throws {
        _ = try await send(method: "POST", path: "/k3s/start", body: nil, as: GuestOK.self)
    }

    public func airgap() async throws -> GuestAirgap {
        try await send(method: "GET", path: "/airgap", body: nil, as: GuestAirgap.self)
    }

    public func importAirgap(
        fileURL: URL,
        name: String,
        onProgress: (@Sendable (Int64, Int64) -> Void)? = nil
    ) async throws -> GuestAirgap {
        let response = try await transport.sendFile(
            method: "PUT",
            path: "/airgap/k3s",
            fileURL: fileURL,
            contentType: "application/octet-stream",
            extraHeaders: ["X-Gmak8-Name": name],
            onProgress: onProgress
        )
        if response.statusCode < 200 || response.statusCode >= 300 {
            let message = (try? JSONDecoder().decode(GuestOK.self, from: response.body))?.error
            throw GuestAgentError.httpStatus(response.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(GuestAirgap.self, from: response.body)
        } catch {
            throw GuestAgentError.decode(String(describing: error))
        }
    }

    public func node() async throws -> GuestNode {
        try await send(method: "GET", path: "/node", body: nil, as: GuestNode.self)
    }

    public func services() async throws -> GuestServiceList {
        try await send(method: "GET", path: "/services", body: nil, as: GuestServiceList.self)
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
