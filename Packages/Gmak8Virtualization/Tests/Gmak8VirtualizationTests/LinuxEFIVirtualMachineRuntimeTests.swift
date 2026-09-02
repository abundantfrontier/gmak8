import Foundation
import Testing

@testable import Gmak8Virtualization

struct LinuxEFIVirtualMachineRuntimeTests {
    @Test func prepareFailsUnsupportedWithoutClaimingALock() throws {
        let env = try makeRuntimeHarness(isSupported: false)
        defer { env.cleanup() }

        #expect(throws: VirtualMachineError.unsupported) {
            try env.runtime.prepare()
        }
        #expect(!env.runtime.holdsDiskLocks)
        let message = VirtualMachineError.unsupported.recoveryMessage
        #expect(!message.lowercased().contains("lock"))
        #expect(!message.lowercased().contains("hypervisor"))
        #expect(message.contains("entitlement") || message.contains("CPU"))
    }

    @Test func prepareLocksDisksWhenSupported() throws {
        let env = try makeRuntimeHarness(isSupported: true)
        defer { env.cleanup() }

        try env.runtime.prepare()
        defer { env.runtime.releaseLocks() }

        #expect(env.runtime.holdsDiskLocks)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: env.layout.osImageLock.path(percentEncoded: false)
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(throws: VirtualMachineError.diskImagesLocked) {
            try DiskFlock().acquire(urls: env.layout.lockURLs)
        }
    }

    @Test func prepareDoesNotTreatMissingSupportAsADiskLock() throws {
        let env = try makeRuntimeHarness(isSupported: false)
        defer { env.cleanup() }

        do {
            try env.runtime.prepare()
            Issue.record("expected unsupported")
        } catch let error as VirtualMachineError {
            #expect(error == .unsupported)
            #expect(error != .diskImagesLocked)
        }
    }

    @Test func hiddenDefaultsReadsOSImagePath() throws {
        let suite = "dev.gmak8.vm.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        try #require(defaults != nil)
        defaults?.removePersistentDomain(forName: suite)
        #expect(VMDefaults.osImageURL(defaults: defaults!) == nil)
        defaults?.set("/tmp/gmak8-os.raw", forKey: VMDefaults.osImageKey)
        #expect(
            VMDefaults.osImageURL(defaults: defaults!)?.path(percentEncoded: false) == "/tmp/gmak8-os.raw"
        )
        defaults?.set("  ", forKey: VMDefaults.osImageKey)
        #expect(VMDefaults.osImageURL(defaults: defaults!) == nil)
        defaults?.removePersistentDomain(forName: suite)
    }

    @Test func missingOverrideOSImageDoesNotCreateASparseFile() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var layout = VMDiskLayout.under(vmDirectory: root)
        layout.osImage = root.appending(path: "missing.raw")
        layout.createOSImageIfMissing = false
        #expect(throws: VirtualMachineError.osImageMissing(layout.osImage)) {
            try layout.ensureFiles(osSize: 1024, dataSize: 1024)
        }
        #expect(!FileManager.default.fileExists(atPath: layout.osImage.path(percentEncoded: false)))
    }

    @Test func sparseImagesAreCreatedMode0600AndLeftInPlace() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "os.img")
        try SparseDiskImage.createIfMissing(at: url, size: 1_048_576)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((attributes[.size] as? NSNumber)?.uint64Value == 1_048_576)
        try SparseDiskImage.createIfMissing(at: url, size: 4096)
        let after = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((after[.size] as? NSNumber)?.uint64Value == 1_048_576)
    }
}

private struct RuntimeHarness {
    var root: URL
    var layout: VMDiskLayout
    var runtime: LinuxEFIVirtualMachineRuntime

    func cleanup() {
        runtime.releaseLocks()
        try? FileManager.default.removeItem(at: root)
    }
}

private func makeRuntimeHarness(isSupported: Bool) throws -> RuntimeHarness {
    let root = try makeTempRoot()
    let layout = VMDiskLayout.under(vmDirectory: root)
    let hardware = VMHardware(
        cpuCount: 1,
        memoryBytes: 64 * 1024 * 1024,
        osDiskBytes: 1_048_576,
        dataDiskBytes: 1_048_576
    )
    let runtime = LinuxEFIVirtualMachineRuntime(
        layout: layout,
        hardware: hardware,
        isSupported: isSupported
    )
    return RuntimeHarness(root: root, layout: layout, runtime: runtime)
}
