import Foundation
import Testing

@testable import Gmak8Kit

struct TimeMachineExclusionTests {
    @Test func createsDirectoryAndInvokesTmutil() throws {
        let spy = RecordingRunner()
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-tm-\(UUID().uuidString)/vm",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try TimeMachineExclusion.excludeVMDirectory(at: directory, runner: spy)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: directory.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        #expect(exists)
        #expect(isDirectory.boolValue)
        #expect(spy.calls.count == 1)
        #expect(spy.calls.first?.executable == TimeMachineExclusion.tmutilPath)
        #expect(spy.calls.first?.arguments == ["addexclusion", directory.path(percentEncoded: false)])
    }

    @Test func missingTmutilStillCreatesDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-tm-\(UUID().uuidString)/vm",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try TimeMachineExclusion.excludeVMDirectory(at: directory, runner: FailingRunner())

        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }
}

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    struct Call {
        var executable: String
        var arguments: [String]
    }

    var calls: [Call] = []

    func run(executable: String, arguments: [String]) throws -> Int32 {
        calls.append(Call(executable: executable, arguments: arguments))
        return 0
    }
}

private struct FailingRunner: CommandRunning {
    func run(executable: String, arguments: [String]) throws -> Int32 {
        throw POSIXError(.ENOENT)
    }
}
