import Foundation

public struct ClusterBringUpResult: Equatable, Sendable {
    public var apiEndpoint: String?

    public init(apiEndpoint: String? = nil) {
        self.apiEndpoint = apiEndpoint
    }
}

public struct ClusterBringUpError: Error, Equatable, LocalizedError, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public protocol ClusterBringUp: Sendable {
    /// Fake VM path skips k3s polling so existing ClusterEngine tests stay one-tick.
    var isNoOp: Bool { get }

    func start(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    )
    func cancel()
}

public struct NoOpClusterBringUp: ClusterBringUp {
    public var isNoOp: Bool { true }

    public init() {}

    public func start(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        completion(.success(ClusterBringUpResult(apiEndpoint: nil)))
    }

    public func cancel() {}
}
