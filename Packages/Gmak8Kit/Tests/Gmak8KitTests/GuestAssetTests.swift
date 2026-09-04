import CryptoKit
import Foundation
import Testing

@testable import Gmak8Kit

struct GuestAssetTests {
    @Test func bundledGuestPinIsLoadedFromModule() throws {
        let pin = try GuestAssetPin.loadFromModule()
        #expect(pin == GuestAssetPin.bundled)
        #expect(pin.fileName == GuestAssetPin.archiveFileName)
        #expect(pin.fileName.hasPrefix("gmak8-guest-"))
        #expect(pin.fileName.hasSuffix("-arm64.raw.zst"))
        #expect(pin.maxBytes == GuestAssetPin.maxCompressedBytes)
        #expect(pin.maxBytes == 500 * 1_024 * 1_024)
        #expect(pin.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
        #expect(!pin.url.absoluteString.lowercased().contains("docker"))
        #expect(!pin.url.absoluteString.contains("docker.io"))
        #expect(!pin.signed.hasStubDigest)
        #expect(pin.signed.remoteDownloadEnabled)
        #expect(pin.signed.chooseFileEnabled)
        #expect(pin.signed.requiresCosign)
        let pem = try CosignPin.loadPublicKeyPEM()
        #expect(pem.contains("BEGIN PUBLIC KEY"))
    }

    @Test func importVerifiesSha256AndProductionCosignBlob() throws {
        let dir = airgapTestdataDirectory()
        let tar = dir.appending(path: "tiny.tar")
        let sig = dir.appending(path: "tiny.tar.sig")
        let pem = try String(contentsOf: dir.appending(path: "cosign.pub"), encoding: .utf8)
        try AirgapVerifier.verifyCosign(file: tar, signature: Data(contentsOf: sig), pem: pem)

        let env = try GuestHarness(archive: tar, signature: sig, pem: pem)
        defer { env.tearDown() }
        let cached = try env.store.importLocalFile(tar, signature: sig)
        #expect(cached == env.store.archiveURL)
        #expect(try env.store.cachedFileIfValid() == env.store.archiveURL)
        let mode =
            try FileManager.default.attributesOfItem(
                atPath: env.store.archiveURL.path(percentEncoded: false)
            )[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func missingLocalFileDoesNotMentionDockerHub() throws {
        let env = try GuestHarness()
        defer { env.tearDown() }
        do {
            _ = try env.store.importLocalFile(env.root.appending(path: "missing.zst"), signature: env.signature)
            Issue.record("expected missing archive")
        } catch let error as SignedAssetError {
            let text = error.localizedDescription
            #expect(text.contains("Choose a file"))
            #expect(!OnboardingCopy.mentionsDockerHub(text))
        }
    }

    @Test func sha256MismatchIsRejected() throws {
        let env = try GuestHarness()
        defer { env.tearDown() }
        try "tampered".write(to: env.archive, atomically: true, encoding: .utf8)
        do {
            _ = try env.store.importLocalFile(env.archive, signature: env.signature)
            Issue.record("expected sha256 mismatch")
        } catch SignedAssetError.sha256Mismatch {
            // expected
        }
    }
}

private func airgapTestdataDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "guest/airgap/testdata", directoryHint: .isDirectory)
}

private struct GuestHarness {
    var root: URL
    var archive: URL
    var signature: URL
    var store: SignedAssetStore

    init(archive: URL? = nil, signature: URL? = nil, pem: String? = nil) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-guest-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let archive, let signature, let pem {
            self.archive = archive
            self.signature = signature
            let sha = try AirgapVerifier.sha256(ofFile: archive)
            let pin = SignedAssetPin(
                fileName: "tiny.tar",
                url: URL(string: "http://127.0.0.1/tiny.tar")!,
                sha256: sha,
                maxBytes: GuestAssetPin.maxCompressedBytes
            )
            store = SignedAssetStore(
                cacheDirectory: root.appending(path: "cache/guest"),
                pin: pin,
                publicKeyPEM: pem,
                label: "guest disk"
            )
            return
        }
        self.archive = root.appending(path: "tiny.tar")
        try Data("gmak8 guest fixture\n".utf8).write(to: self.archive)
        let key = P256.Signing.PrivateKey()
        let generatedPEM = key.publicKey.pemRepresentation
        let blob = try Data(contentsOf: self.archive)
        let sig = try key.signature(for: blob).derRepresentation.base64EncodedString() + "\n"
        self.signature = root.appending(path: "tiny.tar.sig")
        try sig.write(to: self.signature, atomically: true, encoding: .utf8)
        let sha = try AirgapVerifier.sha256(ofFile: self.archive)
        let pin = SignedAssetPin(
            fileName: "tiny.tar",
            url: URL(string: "http://127.0.0.1/tiny.tar")!,
            sha256: sha,
            maxBytes: GuestAssetPin.maxCompressedBytes
        )
        store = SignedAssetStore(
            cacheDirectory: root.appending(path: "cache/guest"),
            pin: pin,
            publicKeyPEM: generatedPEM,
            label: "guest disk"
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
