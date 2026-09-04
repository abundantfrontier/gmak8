import Foundation
import Virtualization

public enum VMConfigurationBuilder {
    public static let diskCachingMode = VZDiskImageCachingMode.cached
    public static let diskSynchronizationMode = VZDiskImageSynchronizationMode.full
    public static let configShareTag = "gmak8-config"

    public static func make(
        layout: VMDiskLayout,
        hardware: VMHardware,
        networkAttachment: VZNetworkDeviceAttachment? = nil,
        configShareDirectory: URL? = nil,
        hostShares: [HostDirectoryShare] = []
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

        if let networkAttachment {
            config.networkDevices = [makeVirtioNetworkDevice(attachment: networkAttachment)]
        }

        // virtio-vsock: guest agent 1024, buildkitd 1025 later. gvproxy is vfkit unixgram, not vsock.
        config.socketDevices = [VZVirtioSocketDeviceConfiguration()]

        var shares: [VZDirectorySharingDeviceConfiguration] = []
        if let configShareDirectory,
            FileManager.default.fileExists(atPath: configShareDirectory.path(percentEncoded: false))
        {
            let share = VZSharedDirectory(url: configShareDirectory, readOnly: true)
            let device = VZVirtioFileSystemDeviceConfiguration(tag: configShareTag)
            device.share = VZSingleDirectoryShare(directory: share)
            shares.append(device)
        }
        for host in hostShares {
            let path = host.url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else {
                continue
            }
            let share = VZSharedDirectory(url: host.url, readOnly: host.readOnly)
            let device = VZVirtioFileSystemDeviceConfiguration(tag: host.tag)
            device.share = VZSingleDirectoryShare(directory: share)
            shares.append(device)
        }
        config.directorySharingDevices = shares

        return config
    }

    public static func makeVirtioNetworkDevice(
        attachment: VZNetworkDeviceAttachment
    ) -> VZVirtioNetworkDeviceConfiguration {
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = attachment
        net.macAddress = VZMACAddress(string: GuestNetwork.guestMACAddress)!
        return net
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
