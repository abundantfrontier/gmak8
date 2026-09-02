import Foundation
import Virtualization

public enum VMConfigurationBuilder {
    public static let diskCachingMode = VZDiskImageCachingMode.cached
    public static let diskSynchronizationMode = VZDiskImageSynchronizationMode.full

    public static func make(
        layout: VMDiskLayout,
        hardware: VMHardware,
        includeNATNetwork: Bool = true
    ) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        config.cpuCount = clampedCPUCount(hardware.cpuCount)
        config.memorySize = clampedMemorySize(hardware.memoryBytes)
        config.platform = VZGenericPlatformConfiguration()

        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = try EFIVariableStore.openOrCreate(at: layout.efiNVRAM)
        config.bootLoader = bootLoader

        config.storageDevices = try makeNVMeStorageDevices(layout: layout)

        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = try VZFileSerialPortAttachment(url: layout.serialLog, append: true)
        config.serialPorts = [serial]

        if includeNATNetwork {
            let net = VZVirtioNetworkDeviceConfiguration()
            net.attachment = VZNATNetworkDeviceAttachment()
            config.networkDevices = [net]
        }

        return config
    }

    public static func makeNVMeStorageDevices(layout: VMDiskLayout) throws -> [VZStorageDeviceConfiguration] {
        let osNVMe = VZNVMExpressControllerDeviceConfiguration(attachment: try makeAttachment(url: layout.osImage))
        let dataNVMe = VZNVMExpressControllerDeviceConfiguration(attachment: try makeAttachment(url: layout.dataImage))
        return [osNVMe, dataNVMe]
    }

    public static func makeAttachment(url: URL) throws -> VZDiskImageStorageDeviceAttachment {
        try VZDiskImageStorageDeviceAttachment(
            url: url,
            readOnly: false,
            cachingMode: diskCachingMode,
            synchronizationMode: diskSynchronizationMode
        )
    }

    public static func clampedCPUCount(_ requested: Int) -> Int {
        let minimum = VZVirtualMachineConfiguration.minimumAllowedCPUCount
        let maximum = VZVirtualMachineConfiguration.maximumAllowedCPUCount
        return min(max(requested, minimum), maximum)
    }

    public static func clampedMemorySize(_ requested: UInt64) -> UInt64 {
        let minimum = VZVirtualMachineConfiguration.minimumAllowedMemorySize
        let maximum = VZVirtualMachineConfiguration.maximumAllowedMemorySize
        return min(max(requested, minimum), maximum)
    }
}
