import Foundation

public struct VMDiskLayout: Equatable, Sendable {
    public var osImage: URL
    public var dataImage: URL
    public var efiNVRAM: URL
    public var serialLog: URL
    public var createOSImageIfMissing: Bool

    public init(
        osImage: URL,
        dataImage: URL,
        efiNVRAM: URL,
        serialLog: URL,
        createOSImageIfMissing: Bool = true
    ) {
        self.osImage = osImage
        self.dataImage = dataImage
        self.efiNVRAM = efiNVRAM
        self.serialLog = serialLog
        self.createOSImageIfMissing = createOSImageIfMissing
    }

    public static func under(vmDirectory: URL) -> VMDiskLayout {
        VMDiskLayout(
            osImage: vmDirectory.appending(path: "os.img"),
            dataImage: vmDirectory.appending(path: "data.img"),
            efiNVRAM: vmDirectory.appending(path: "efi-nvram.bin"),
            serialLog: vmDirectory.appending(path: "serial.log")
        )
    }

    public var osImageLock: URL {
        Self.lockURL(for: osImage)
    }

    public var dataImageLock: URL {
        Self.lockURL(for: dataImage)
    }

    public var lockURLs: [URL] {
        [osImageLock, dataImageLock]
    }

    public static func lockURL(for image: URL) -> URL {
        URL(fileURLWithPath: image.path(percentEncoded: false) + ".lock")
    }

    public func ensureFiles(osSize: UInt64, dataSize: UInt64, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: dataImage.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: osImage.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: efiNVRAM.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: serialLog.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if createOSImageIfMissing {
            try SparseDiskImage.createIfMissing(at: osImage, size: osSize, fileManager: fileManager)
        } else if !fileManager.fileExists(atPath: osImage.path(percentEncoded: false)) {
            throw VirtualMachineError.osImageMissing(osImage)
        }
        try SparseDiskImage.createIfMissing(at: dataImage, size: dataSize, fileManager: fileManager)
        try SparseDiskImage.createEmptyIfMissing(at: serialLog, fileManager: fileManager)
    }
}
