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
    /// When true, the engine marks `running` as soon as VM start succeeds.
    var isNoOp: Bool { get }

    func start(
        generation: UInt64,
        isCurrent: @escaping @Sendable (UInt64) -> Bool,
        setStep: @escaping @Sendable (String) -> Void,
        log: @escaping @Sendable (String) -> Void,
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
        log: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<ClusterBringUpResult, any Error>) -> Void
    ) {
        completion(.success(ClusterBringUpResult(apiEndpoint: nil)))
    }

    public func cancel() {}
}
