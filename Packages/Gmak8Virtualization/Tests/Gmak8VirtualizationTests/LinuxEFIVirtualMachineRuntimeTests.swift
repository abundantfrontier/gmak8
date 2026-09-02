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
        #expect(VMDefaults.suiteName == "dev.gmak8.core")
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

    @Test func cancelDuringPrepareDoesNotCreateAVM() throws {
        let env = try makeRuntimeHarness(isSupported: true)
        defer { env.cleanup() }

        env.runtime.prepareHook = { env.runtime.cancelInFlightStart() }
        let box = ResultBox()
        env.runtime.start { result in
            box.set(result)
        }
        #expect(box.result != nil)
        if case .failure(let error as VirtualMachineError) = box.result {
            #expect(error == .stoppedDuringStart)
        } else {
            Issue.record("expected stoppedDuringStart")
        }
        #expect(!env.runtime.holdsDiskLocks)
    }

    @Test func kubernetesDefaultsUseSixtyGibDataDisk() {
        let small = VMHardware.kubernetesDefaults(processorCount: 8, physicalMemoryBytes: 8 * VMHardware.gibibyte)
        #expect(small.dataDiskBytes == 60 * VMHardware.gibibyte)
        #expect(small.osDiskBytes == 8 * VMHardware.gibibyte)
        #expect(small.cpuCount == 4)
        #expect(small.memoryBytes == 4 * VMHardware.gibibyte)
        let large = VMHardware.kubernetesDefaults(processorCount: 10, physicalMemoryBytes: 16 * VMHardware.gibibyte)
        #expect(large.memoryBytes == 6 * VMHardware.gibibyte)
        #expect(large.dataDiskBytes == 60 * VMHardware.gibibyte)
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

    @Test func prepareFailsWhenVfkitSocketPathIsTooLong() throws {
        let env = try makeRuntimeHarness(isSupported: true)
        defer { env.cleanup() }
        let tooLong = URL(
            fileURLWithPath: "/" + String(repeating: "x", count: 120) + "/n.sock"
        )
        let network = GVProxyNetworkStack(
            executable: URL(fileURLWithPath: "/usr/bin/true"),
            httpSocket: URL(fileURLWithPath: "/tmp/g.sock"),
            vfkitSocket: tooLong
        )
        let runtime = LinuxEFIVirtualMachineRuntime(
            layout: env.layout,
            hardware: VMHardware(
                cpuCount: 1,
                memoryBytes: 64 * 1024 * 1024,
                osDiskBytes: 1_048_576,
                dataDiskBytes: 1_048_576
            ),
            isSupported: true,
            network: network
        )
        do {
            try runtime.prepare()
            Issue.record("expected socketPathTooLong")
        } catch let error as VirtualMachineError {
            guard case .socketPathTooLong = error else {
                Issue.record("unexpected \(error)")
                return
            }
            #expect(error.recoveryMessage.contains("too long"))
        }
        #expect(!runtime.holdsDiskLocks)
    }

    @Test func prepareFailsWhenGvproxyIsMissing() throws {
        let env = try makeRuntimeHarness(isSupported: true)
        defer { env.cleanup() }
        let http = env.root.appending(path: "g.sock")
        let vfkit = env.root.appending(path: "n.sock")
        let network = GVProxyNetworkStack(
            executable: env.root.appending(path: "missing-gvproxy"),
            httpSocket: http,
            vfkitSocket: vfkit
        )
        let runtime = LinuxEFIVirtualMachineRuntime(
            layout: env.layout,
            hardware: VMHardware(
                cpuCount: 1,
                memoryBytes: 64 * 1024 * 1024,
                osDiskBytes: 1_048_576,
                dataDiskBytes: 1_048_576
            ),
            isSupported: true,
            network: network
        )
        #expect(throws: VirtualMachineError.gvproxyMissing(env.root.appending(path: "missing-gvproxy"))) {
            try runtime.prepare()
        }
        #expect(!runtime.holdsDiskLocks)
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

private final class ResultBox: @unchecked Sendable {
    var result: Result<Void, any Error>?
    func set(_ result: Result<Void, any Error>) {
        self.result = result
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
