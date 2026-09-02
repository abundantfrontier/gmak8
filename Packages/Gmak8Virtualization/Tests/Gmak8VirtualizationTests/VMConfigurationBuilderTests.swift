import Foundation
import Testing
import Virtualization

@testable import Gmak8Virtualization

struct VMConfigurationBuilderTests {
    @Test func nvmeAttachmentsUseCachedFullAndNotVirtioBlk() throws {
        let env = try makeLayoutHarness()
        defer { env.cleanup() }

        let devices = try VMConfigurationBuilder.makeNVMeStorageDevices(layout: env.layout)
        #expect(devices.count == 2)
        let osNVMe = devices[0] as? VZNVMExpressControllerDeviceConfiguration
        let dataNVMe = devices[1] as? VZNVMExpressControllerDeviceConfiguration
        try #require(osNVMe != nil && dataNVMe != nil)

        let osAttachment = osNVMe?.attachment as? VZDiskImageStorageDeviceAttachment
        let dataAttachment = dataNVMe?.attachment as? VZDiskImageStorageDeviceAttachment
        try #require(osAttachment != nil)
        try #require(dataAttachment != nil)

        #expect(osAttachment?.url.standardizedFileURL == env.layout.osImage.standardizedFileURL)
        #expect(dataAttachment?.url.standardizedFileURL == env.layout.dataImage.standardizedFileURL)
        #expect(osAttachment?.isReadOnly == false)
        #expect(dataAttachment?.isReadOnly == false)
        #expect(osAttachment?.cachingMode == .cached)
        #expect(dataAttachment?.cachingMode == .cached)
        #expect(osAttachment?.synchronizationMode == .full)
        #expect(dataAttachment?.synchronizationMode == .full)

        #expect(VMConfigurationBuilder.diskCachingMode == .cached)
        #expect(VMConfigurationBuilder.diskSynchronizationMode == .full)

        let config = try VMConfigurationBuilder.make(layout: env.layout, hardware: env.hardware)
        #expect(config.storageDevices.count == 2)
        for device in config.storageDevices {
            #expect(device is VZNVMExpressControllerDeviceConfiguration)
            #expect(!(device is VZVirtioBlockDeviceConfiguration))
        }
    }

    @Test func configurationUsesEFISerialWithoutNAT() throws {
        let env = try makeLayoutHarness()
        defer { env.cleanup() }

        let config = try VMConfigurationBuilder.make(layout: env.layout, hardware: env.hardware)
        #expect(config.bootLoader is VZEFIBootLoader)
        let efi = config.bootLoader as? VZEFIBootLoader
        #expect(efi?.variableStore != nil)
        #expect(
            efi?.variableStore?.url.standardizedFileURL == env.layout.efiNVRAM.standardizedFileURL
        )
        #expect(config.platform is VZGenericPlatformConfiguration)
        #expect(config.serialPorts.count == 1)
        #expect(config.serialPorts[0] is VZVirtioConsoleDeviceSerialPortConfiguration)
        #expect(config.serialPorts[0].attachment is VZFileSerialPortAttachment)
        #expect(config.networkDevices.isEmpty)
        #expect(config.cpuCount == 2)
        #expect(config.memorySize == 256 * 1024 * 1024)
    }

    @Test func configurationPinsGuestMACOnFileHandleNIC() throws {
        let env = try makeLayoutHarness()
        defer { env.cleanup() }

        let pair = try datagramSocketPair()
        defer {
            try? pair.0.close()
            try? pair.1.close()
        }
        let attachment = VZFileHandleNetworkDeviceAttachment(fileHandle: pair.0)
        let config = try VMConfigurationBuilder.make(
            layout: env.layout,
            hardware: env.hardware,
            networkAttachment: attachment
        )
        #expect(config.networkDevices.count == 1)
        #expect(config.networkDevices[0].attachment is VZFileHandleNetworkDeviceAttachment)
        #expect(!(config.networkDevices[0].attachment is VZNATNetworkDeviceAttachment))
        #expect(config.networkDevices[0].macAddress.string.lowercased() == GuestNetwork.guestMACAddress)
    }

    @Test func recreateNVRAMOverwritesExistingStore() throws {
        let env = try makeLayoutHarness()
        defer { env.cleanup() }

        let first = try EFIVariableStore.openOrCreate(at: env.layout.efiNVRAM)
        #expect(FileManager.default.fileExists(atPath: env.layout.efiNVRAM.path(percentEncoded: false)))
        let recreated = try EFIVariableStore.recreate(at: env.layout.efiNVRAM)
        #expect(first.url.standardizedFileURL == recreated.url.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: env.layout.efiNVRAM.path(percentEncoded: false)))
    }

    @Test func queueLabelIsDedicatedSerialVMQueue() {
        #expect(VirtualMachineQueue.label == "dev.gmak8.vm")
        #expect(VirtualMachineQueue.shared.label == "dev.gmak8.vm")
    }
}

private struct LayoutHarness {
    var root: URL
    var layout: VMDiskLayout
    var hardware: VMHardware

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func makeLayoutHarness() throws -> LayoutHarness {
    let root = try makeTempRoot()
    let layout = VMDiskLayout.under(vmDirectory: root)
    let hardware = VMHardware(
        cpuCount: 2,
        memoryBytes: 256 * 1024 * 1024,
        osDiskBytes: 1_048_576,
        dataDiskBytes: 1_048_576
    )
    try layout.ensureFiles(osSize: hardware.osDiskBytes, dataSize: hardware.dataDiskBytes)
    return LayoutHarness(root: root, layout: layout, hardware: hardware)
}
