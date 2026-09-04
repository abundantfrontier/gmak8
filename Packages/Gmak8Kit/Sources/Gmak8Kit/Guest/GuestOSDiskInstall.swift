import Foundation

/// Install a local Linux disk as `os.img`. This is the bring-up path while the guest pin is a stub.
public enum GuestOSDiskInstall {
    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case missingSource(String)
        case k3sImagePack
        case notAGuestDisk
        case decompressFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingSource(let path):
                return "Guest disk missing at \(path)."
            case .k3sImagePack:
                return
                    "That file is Kubernetes container images. The VM disk is a Linux .img or .raw."
            case .notAGuestDisk:
                return "That file has no bootable guest. Pick a Linux .img or .raw."
            case .decompressFailed(let message):
                return message
            }
        }
    }

    public static func looksLikeK3sImagePack(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("k3s-airgap") || lower.contains("airgap-images") || lower.contains(".tar.")
    }

    public static func containsBootSignature(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 1024), prefix.count >= 512 else {
            return false
        }
        if prefix.count >= 520, prefix.subdata(in: 512..<520) == Data("EFI PART".utf8) {
            return true
        }
        return prefix[510] == 0x55 && prefix[511] == 0xAA
    }

    public static func install(
        from source: URL,
        to osImage: URL,
        fileManager: FileManager = .default
    ) throws {
        let name = source.lastPathComponent
        if looksLikeK3sImagePack(name: name) {
            throw Failure.k3sImagePack
        }
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw Failure.missingSource(source.path(percentEncoded: false))
        }
        var scratch: URL?
        let working: URL
        if name.lowercased().hasSuffix(".zst") {
            let unpacked = try decompressZstd(from: source, fileManager: fileManager)
            scratch = unpacked
            working = unpacked
        } else {
            working = source
        }
        defer {
            if let scratch {
                try? fileManager.removeItem(at: scratch)
            }
        }
        guard containsBootSignature(at: working) else {
            throw Failure.notAGuestDisk
        }
        try AtomicFileReplace.copy(from: working, to: osImage, posixPermissions: 0o600, fileManager: fileManager)
    }

    private static func decompressZstd(from source: URL, fileManager: FileManager) throws -> URL {
        guard let executable = zstdExecutable(fileManager: fileManager) else {
            throw Failure.decompressFailed("Compressed guest needs zstd, or pick an uncompressed .img or .raw.")
        }
        let dest = fileManager.temporaryDirectory.appending(path: "gmak8-guest-\(UUID().uuidString).img")
        if !fileManager.createFile(atPath: dest.path(percentEncoded: false), contents: nil, attributes: [.posixPermissions: 0o600]) {
            throw Failure.decompressFailed("Could not create a temporary guest disk.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-dc", source.path(percentEncoded: false)]
        let output = try FileHandle(forWritingTo: dest)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            try output.close()
        } catch {
            try? fileManager.removeItem(at: dest)
            throw Failure.decompressFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            try? fileManager.removeItem(at: dest)
            throw Failure.decompressFailed("zstd exited \(process.terminationStatus).")
        }
        return dest
    }

    private static func zstdExecutable(fileManager: FileManager) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/zstd",
            "/usr/local/bin/zstd",
            "/usr/bin/zstd",
        ]
        return candidates.map { URL(fileURLWithPath: $0) }.first { url in
            fileManager.isExecutableFile(atPath: url.path(percentEncoded: false))
        }
    }
}
