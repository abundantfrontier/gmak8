import Foundation
import Testing
import Virtualization

@testable import Gmak8Virtualization

struct DiskFlockTests {
    @Test func exclusiveLockRejectsSecondHolder() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appending(path: "os.img.lock")

        let first = DiskFlock()
        try first.acquire(urls: [lockURL])
        defer { first.release() }

        let second = DiskFlock()
        #expect(throws: VirtualMachineError.diskImagesLocked) {
            try second.acquire(urls: [lockURL])
        }
        #expect(!second.isHolding)
        #expect(first.isHolding)
    }

    @Test func lockFilesAreMode0600AndNotUnlinkedOnRelease() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let osLock = root.appending(path: "os.img.lock")
        let dataLock = root.appending(path: "data.img.lock")

        let flock = DiskFlock()
        try flock.acquire(urls: [osLock, dataLock])
        for url in [osLock, dataLock] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        flock.release()
        #expect(FileManager.default.fileExists(atPath: osLock.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: dataLock.path(percentEncoded: false)))
    }

    @Test func lockFileKeepsInodeAcrossRelease() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appending(path: "data.img.lock")

        let first = DiskFlock()
        try first.acquire(urls: [lockURL])
        let firstInode =
            try FileManager.default.attributesOfItem(
                atPath: lockURL.path(percentEncoded: false)
            )[.systemFileNumber] as? NSNumber
        first.release()
        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))

        let second = DiskFlock()
        try second.acquire(urls: [lockURL])
        defer { second.release() }
        let secondInode =
            try FileManager.default.attributesOfItem(
                atPath: lockURL.path(percentEncoded: false)
            )[.systemFileNumber] as? NSNumber
        #expect(firstInode != nil)
        #expect(firstInode == secondInode)
    }

    @Test func secondImageLockFailureReleasesTheFirst() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let osLock = root.appending(path: "os.img.lock")
        let dataLock = root.appending(path: "data.img.lock")

        let holder = DiskFlock()
        try holder.acquire(urls: [dataLock])
        defer { holder.release() }

        let attempt = DiskFlock()
        #expect(throws: VirtualMachineError.diskImagesLocked) {
            try attempt.acquire(urls: [osLock, dataLock])
        }
        #expect(!attempt.isHolding)

        let osHolder = DiskFlock()
        try osHolder.acquire(urls: [osLock])
        defer { osHolder.release() }
        #expect(osHolder.isHolding)
    }

    @Test func isSupportedDoesNotChangeWhenDisksAreLocked() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appending(path: "os.img.lock")
        let before = VZVirtualMachine.isSupported

        let flock = DiskFlock()
        try flock.acquire(urls: [lockURL])
        defer { flock.release() }

        #expect(VZVirtualMachine.isSupported == before)
        #expect(throws: VirtualMachineError.diskImagesLocked) {
            try DiskFlock().acquire(urls: [lockURL])
        }
        #expect(VZVirtualMachine.isSupported == before)
    }
}

func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "gmak8-vm-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
