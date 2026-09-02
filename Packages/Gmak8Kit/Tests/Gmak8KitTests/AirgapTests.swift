import CryptoKit
import Darwin
import Foundation
import Testing

@testable import Gmak8Kit

struct AirgapTests {
    @Test func bundledPinMatchesConstantsAndOfficialHash() throws {
        let pin = try AirgapPin.loadFromModule()
        #expect(pin == AirgapPin.bundled)
        #expect(pin.k3sVersion == K3sPin.version)
        #expect(pin.fileName == AirgapPin.archiveFileName)
        #expect(pin.maxBytes == AirgapPin.maxCompressedBytes)
        #expect(pin.maxBytes == 500 * 1_024 * 1_024)
        #expect(pin.maxBytes < AirgapPin.githubReleaseMaxBytes)
        #expect(pin.guestImagesDirectory == AirgapPin.guestImagesDirectory)
        #expect(pin.sha256 == "c12ec7b122f34eb1f89310b05e66b500a2f49522d7cd4ceb3475a675cab6ebc6")
        #expect(pin.url.absoluteString.contains("%2B"))
        #expect(pin.url.absoluteString.contains("k3s-airgap-images-arm64.tar.zst"))
        let pem = try CosignPin.loadPublicKeyPEM()
        #expect(pem.contains("BEGIN PUBLIC KEY"))
        #expect(!pem.contains("PRIVATE KEY"))
        _ = try P256.Signing.PublicKey(pemRepresentation: pem)
    }

    @Test func sizeHeadroomIsArchivePlusTwentyPercent() {
        #expect(AirgapVerifier.requiredFreeBytes(archiveBytes: 100) == 120)
        #expect(AirgapVerifier.fitsOnDataDisk(archiveBytes: 100, bytesFree: 120))
        #expect(!AirgapVerifier.fitsOnDataDisk(archiveBytes: 100, bytesFree: 119))
        #expect(AirgapVerifier.requiredFreeBytes(archiveBytes: AirgapPin.maxCompressedBytes) == 600 * 1_024 * 1_024)
    }

    @Test func importLocalFileVerifiesSha256AndCosign() throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }

        _ = try env.store.importLocalFile(env.archive, signature: env.signature)
        #expect(FileManager.default.fileExists(atPath: env.store.archiveURL.path(percentEncoded: false)))
        let mode =
            try FileManager.default.attributesOfItem(
                atPath: env.store.archiveURL.path(percentEncoded: false)
            )[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(try env.store.cachedFileIfValid() == env.store.archiveURL)
    }

    @Test func sha256MismatchIsRejected() throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }
        try "tampered".write(to: env.archive, atomically: true, encoding: .utf8)
        do {
            _ = try env.store.importLocalFile(env.archive, signature: env.signature)
            Issue.record("expected sha256 mismatch")
        } catch AirgapError.sha256Mismatch {
            // expected
        }
    }

    @Test func cosignMismatchIsRejected() throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }
        let other = P256.Signing.PrivateKey()
        let blob = try Data(contentsOf: env.archive)
        let sig = try other.signature(for: blob).derRepresentation.base64EncodedString()
        try sig.write(to: env.signature, atomically: true, encoding: .utf8)
        do {
            _ = try env.store.importLocalFile(env.archive, signature: env.signature)
            Issue.record("expected cosign failure")
        } catch AirgapError.cosignVerifyFailed {
            // expected
        }
    }

    @Test func missingLocalFileMentionsDockerHub() throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }
        do {
            _ = try env.store.importLocalFile(env.root.appending(path: "missing.tar"), signature: env.signature)
            Issue.record("expected missing archive")
        } catch let error as AirgapError {
            #expect(error.localizedDescription.contains("docker.io/rancher"))
        }
    }

    @Test func downloadFromLocalHTTPCachesVerifiedArchive() async throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }
        let server = try AirgapHTTPServer(archive: env.archive, signature: env.signature)
        defer { server.stop() }

        let pin = AirgapPin(
            k3sVersion: env.pin.k3sVersion,
            fileName: env.pin.fileName,
            url: server.archiveURL,
            sha256: env.pin.sha256,
            maxBytes: env.pin.maxBytes,
            guestImagesDirectory: env.pin.guestImagesDirectory
        )
        let store = AirgapStore(paths: env.paths, pin: pin, publicKeyPEM: env.pem)
        let cached = try await store.download(signatureURL: server.signatureURL)
        #expect(cached == store.archiveURL)
        #expect(try AirgapVerifier.sha256(ofFile: cached) == pin.sha256)
    }

    @Test func tooLargeArchiveIsRejected() throws {
        let env = try AirgapHarness()
        defer { env.tearDown() }
        let pin = AirgapPin(
            k3sVersion: env.pin.k3sVersion,
            fileName: env.pin.fileName,
            url: env.pin.url,
            sha256: env.pin.sha256,
            maxBytes: 4,
            guestImagesDirectory: env.pin.guestImagesDirectory
        )
        let store = AirgapStore(paths: env.paths, pin: pin, publicKeyPEM: env.pem)
        do {
            _ = try store.importLocalFile(env.archive, signature: env.signature)
            Issue.record("expected too large")
        } catch AirgapError.tooLarge {
            // expected
        }
    }

    @Test func verifyCosignAcceptsCosignSignBlobFixture() throws {
        let dir = airgapTestdataDirectory()
        let tar = dir.appending(path: "tiny.tar")
        let sig = dir.appending(path: "tiny.tar.sig")
        let pem = try String(contentsOf: dir.appending(path: "cosign.pub"), encoding: .utf8)
        #expect(pem.contains("BEGIN PUBLIC KEY"))
        try AirgapVerifier.verifyCosign(file: tar, signature: Data(contentsOf: sig), pem: pem)
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

private struct AirgapHarness {
    var root: URL
    var paths: HostPaths
    var archive: URL
    var signature: URL
    var pin: AirgapPin
    var pem: String
    var store: AirgapStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-airgap-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = HostPaths(
            applicationSupport: root.appending(path: "Application Support/dev.gmak8.app"),
            caches: root.appending(path: "Caches/dev.gmak8.app"),
            logs: root.appending(path: "Logs/gmak8")
        )
        archive = root.appending(path: "tiny.tar")
        try Data("gmak8 airgap fixture\n".utf8).write(to: archive)
        let key = P256.Signing.PrivateKey()
        pem = key.publicKey.pemRepresentation
        let blob = try Data(contentsOf: archive)
        let sig = try key.signature(for: blob).derRepresentation.base64EncodedString() + "\n"
        signature = root.appending(path: "tiny.tar.sig")
        try sig.write(to: signature, atomically: true, encoding: .utf8)
        let sha = try AirgapVerifier.sha256(ofFile: archive)
        pin = AirgapPin(
            k3sVersion: K3sPin.version,
            fileName: "tiny.tar",
            url: URL(string: "http://127.0.0.1/tiny.tar")!,
            sha256: sha,
            maxBytes: AirgapPin.maxCompressedBytes,
            guestImagesDirectory: AirgapPin.guestImagesDirectory
        )
        store = AirgapStore(paths: paths, pin: pin, publicKeyPEM: pem)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class AirgapHTTPServer: @unchecked Sendable {
    private let listenFD: Int32
    private let queue = DispatchQueue(label: "gmak8.kit.test.airgap.http")
    private var source: DispatchSourceRead?
    private let archive: Data
    private let signature: Data
    let port: UInt16

    var archiveURL: URL { URL(string: "http://127.0.0.1:\(port)/tiny.tar")! }
    var signatureURL: URL { URL(string: "http://127.0.0.1:\(port)/tiny.tar.sig")! }

    init(archive: URL, signature: URL) throws {
        self.archive = try Data(contentsOf: archive)
        self.signature = try Data(contentsOf: signature)
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        if listen(fd, 8) != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        if nameResult != 0 {
            Darwin.close(fd)
            throw POSIXError(.EIO)
        }
        listenFD = fd
        port = UInt16(bigEndian: bound.sin_port)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOnce()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        Darwin.close(listenFD)
    }

    private func acceptOnce() {
        let client = accept(listenFD, nil, nil)
        if client < 0 {
            return
        }
        queue.async { [archive, signature] in
            defer { Darwin.close(client) }
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4096)
            while buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) == nil {
                let count = Darwin.read(client, &chunk, chunk.count)
                if count <= 0 {
                    return
                }
                buffer.append(contentsOf: chunk.prefix(count))
                if buffer.count > 65_536 {
                    return
                }
            }
            let header = String(data: buffer, encoding: .utf8) ?? ""
            let body: Data
            if header.contains("tiny.tar.sig") {
                body = signature
            } else if header.contains("tiny.tar") {
                body = archive
            } else {
                let msg = Data("not found".utf8)
                let resp = "HTTP/1.1 404 OK\r\nContent-Length: \(msg.count)\r\nConnection: close\r\n\r\n"
                var payload = Data(resp.utf8)
                payload.append(msg)
                payload.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                        return
                    }
                    _ = Darwin.write(client, base, raw.count)
                }
                return
            }
            let resp =
                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(resp.utf8)
            payload.append(body)
            payload.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(client, base + offset, raw.count - offset)
                    if written <= 0 {
                        return
                    }
                    offset += written
                }
            }
        }
    }
}
