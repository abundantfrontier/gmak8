import Foundation

public enum EngineReadyPoll {
    public static let defaultAttempts = 50

    public static func wait(attempts: Int = defaultAttempts, isReady: () throws -> Bool) rethrows -> Bool {
        var remaining = attempts
        while remaining > 0 {
            if try isReady() {
                return true
            }
            remaining -= 1
        }
        return false
    }
}
