import Foundation
import Testing

@testable import Gmak8Kit

struct MkosiWorkingDirectoryTests {
    @Test func resolvesRepoRootAndMkosiDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-mkosi-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let mkosi = MkosiWorkingDirectory.directory(inRepoRoot: root)
        try FileManager.default.createDirectory(at: mkosi, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("# mkosi\n".utf8).write(to: mkosi.appending(path: "mkosi.conf"))

        #expect(MkosiWorkingDirectory.isMkosiDirectory(mkosi))
        #expect(MkosiWorkingDirectory.resolved(fromPicked: mkosi) == mkosi)
        #expect(MkosiWorkingDirectory.resolved(fromPicked: root) == mkosi)
        #expect(
            MkosiWorkingDirectory.resolve(home: root.deletingLastPathComponent(), savedRepoPath: root.path)
                == mkosi
        )
    }
}
