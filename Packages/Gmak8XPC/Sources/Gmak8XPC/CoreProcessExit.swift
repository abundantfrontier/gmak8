import Foundation

public protocol ProcessExiting: Sendable {
    func exitProcess(code: Int32)
}

/// Default for tests: never terminate the test runner.
public struct NoProcessExit: ProcessExiting {
    public init() {}

    public func exitProcess(code: Int32) {}
}

/// Production hook. `gmak8-core` sets a handler that stops `engine.sock` then exits.
public final class CoreProcessExit: ProcessExiting, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Int32) -> Void)?

    public init() {}

    public func setHandler(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func exitProcess(code: Int32) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        if let handler {
            handler(code)
        } else {
            Foundation.exit(code)
        }
    }
}
