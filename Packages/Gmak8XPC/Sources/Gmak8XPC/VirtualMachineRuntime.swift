import Foundation

public struct VirtualMachinePreflightError: Equatable, Sendable {
    public var code: EngineErrorCode
    public var message: String

    public init(code: EngineErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public protocol VirtualMachineRuntime: Sendable {
    var stepName: String { get }
    func preflight() -> VirtualMachinePreflightError?
    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void)
    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void)
    func setUnexpectedStopHandler(_ handler: (@Sendable (Error?) -> Void)?)
    func cancelInFlightStart()
}

extension VirtualMachineRuntime {
    public func setUnexpectedStopHandler(_ handler: (@Sendable (Error?) -> Void)?) {}
    public func cancelInFlightStart() {}
}

public struct FakeVirtualMachineRuntime: VirtualMachineRuntime {
    public init() {}

    public var stepName: String { "fakeVM" }

    public func preflight() -> VirtualMachinePreflightError? {
        nil
    }

    public func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }

    public func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }
}
