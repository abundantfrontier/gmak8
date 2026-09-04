import Foundation
import Testing

@testable import Gmak8Kit

struct GuestOSDiskInstallTests {
    @Test func k3sAirgapNameIsRejected() {
        #expect(GuestOSDiskInstall.looksLikeK3sImagePack(name: "k3s-airgap-images-arm64.tar.zst"))
        #expect(GuestOSDiskInstall.looksLikeK3sImagePack(name: "gmak8-k3s-airgap-v1.33.3-arm64.tar.zst"))
        #expect(!GuestOSDiskInstall.looksLikeK3sImagePack(name: "gmak8-guest-0.0.1-arm64.raw"))
        #expect(!GuestOSDiskInstall.looksLikeK3sImagePack(name: "os.img"))
    }

    @Test func emptySparseFileIsNotAGuest() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gmak8-guest-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appending(path: "empty.img")
        FileManager.default.createFile(atPath: empty.path(percentEncoded: false), contents: Data(count: 1024))
        #expect(!GuestOSDiskInstall.containsBootSignature(at: empty))
        let dest = root.appending(path: "os.img")
        #expect(throws: GuestOSDiskInstall.Failure.notAGuestDisk) {
            try GuestOSDiskInstall.install(from: empty, to: dest)
        }
    }

    @Test func gptHeaderInstallsAsOsImage() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gmak8-guest-gpt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var prefix = Data(count: 1024)
        prefix.replaceSubrange(512..<520, with: Data("EFI PART".utf8))
        let source = root.appending(path: "guest.raw")
        try prefix.write(to: source)
        let dest = root.appending(path: "os.img")
        try GuestOSDiskInstall.install(from: source, to: dest)
        #expect(GuestOSDiskInstall.containsBootSignature(at: dest))
    }

    @Test func k3sPackInstallThrows() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gmak8-guest-k3s-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "k3s-airgap-images-arm64.tar.zst")
        try Data("not-a-disk".utf8).write(to: source)
        #expect(throws: GuestOSDiskInstall.Failure.k3sImagePack) {
            try GuestOSDiskInstall.install(from: source, to: root.appending(path: "os.img"))
        }
    }
}
