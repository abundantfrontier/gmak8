import Foundation

public protocol CommandRunning {
    @discardableResult
    func run(executable: String, arguments: [String]) throws -> Int32
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

public enum TimeMachineExclusion {
    public static let tmutilPath = "/usr/bin/tmutil"

    /// Creates `vm/` if needed. A missing or failing `tmutil` must not fail the caller.
    public static func excludeVMDirectory(
        at url: URL,
        fileManager: FileManager = .default,
        runner: any CommandRunning = ProcessCommandRunner()
    ) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        do {
            _ = try runner.run(
                executable: tmutilPath,
                arguments: ["addexclusion", url.path(percentEncoded: false)]
            )
        } catch {
            // Time Machine is optional in CI and on hosts without tmutil.
        }
    }
}
