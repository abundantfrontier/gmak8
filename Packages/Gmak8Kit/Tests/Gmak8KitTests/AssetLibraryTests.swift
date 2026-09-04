import Foundation
import Testing

@testable import Gmak8Kit

struct AssetLibraryTests {
    @Test func defaultRootIsHomeGmak8() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(AssetLibrary.defaultRoot(home: home).lastPathComponent == "gmak8")
        #expect(
            AssetLibrary.resolvedRoot(libraryFolderPath: nil, home: home)
                == AssetLibrary.defaultRoot(home: home)
        )
        #expect(
            AssetLibrary.resolvedRoot(libraryFolderPath: "/tmp/lab", home: home).path
                == "/tmp/lab"
        )
    }

    @Test func scanSeparatesGuestDisksFromK3sPacks() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-lib-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try AssetLibrary.ensureLayout(at: root)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("disk".utf8).write(
            to: root.appending(path: "guest", directoryHint: .isDirectory).appending(path: "debian.img")
        )
        try Data("pack".utf8).write(
            to: root.appending(path: "k3s", directoryHint: .isDirectory).appending(
                path: "k3s-airgap-images-arm64.tar.zst"
            )
        )
        try Data("root".utf8).write(to: root.appending(path: "extra.raw"))

        let scanned = AssetLibrary.scan(root: root)
        #expect(scanned.guest.map(\.relativePath).sorted() == ["extra.raw", "guest/debian.img"])
        #expect(scanned.k3s.map(\.relativePath) == ["k3s/k3s-airgap-images-arm64.tar.zst"])
        #expect(!scanned.guest.contains { $0.relativePath.contains("airgap") })
    }

    @Test func preferredGuestDiskPrefersBootableImgOverZst() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-pref-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try AssetLibrary.ensureLayout(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let guest = root.appending(path: "guest", directoryHint: .isDirectory)
        var gpt = Data(count: 1024)
        gpt.replaceSubrange(512..<520, with: Data("EFI PART".utf8))
        let img = guest.appending(path: "os.img")
        try gpt.write(to: img)
        try Data("compressed".utf8).write(to: guest.appending(path: "os.img.zst"))
        try Data(count: 1024).write(to: guest.appending(path: "empty.img"))
        let scanned = AssetLibrary.scan(root: root)
        let preferred = AssetLibrary.preferredGuestDisk(scanned.guest)
        #expect(preferred?.relativePath == "guest/os.img")
        #expect(GuestOSDiskInstall.containsBootSignature(at: img))
    }

    @Test func preferredGuestDiskFallsBackToZst() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-zst-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try AssetLibrary.ensureLayout(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("compressed".utf8).write(
            to: root.appending(path: "guest", directoryHint: .isDirectory).appending(path: "os.img.zst")
        )
        let scanned = AssetLibrary.scan(root: root)
        #expect(AssetLibrary.preferredGuestDisk(scanned.guest)?.relativePath == "guest/os.img.zst")
    }
}
