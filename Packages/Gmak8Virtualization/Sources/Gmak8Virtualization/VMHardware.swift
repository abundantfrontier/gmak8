public struct VMHardware: Equatable, Sendable {
    public static let gibibyte: UInt64 = 1024 * 1024 * 1024
    public static let defaultOSDiskBytes: UInt64 = 8 * gibibyte
    public static let kubernetesDataDiskBytes: UInt64 = 60 * gibibyte

    public var cpuCount: Int
    public var memoryBytes: UInt64
    public var osDiskBytes: UInt64
    public var dataDiskBytes: UInt64

    public init(cpuCount: Int, memoryBytes: UInt64, osDiskBytes: UInt64, dataDiskBytes: UInt64) {
        self.cpuCount = cpuCount
        self.memoryBytes = memoryBytes
        self.osDiskBytes = osDiskBytes
        self.dataDiskBytes = dataDiskBytes
    }

    public static func kubernetesDefaults(
        processorCount: Int,
        physicalMemoryBytes: UInt64
    ) -> VMHardware {
        let cpu = min(4, max(1, processorCount - 2))
        let memoryGiB: UInt64 = physicalMemoryBytes / gibibyte >= 16 ? 6 : 4
        return VMHardware(
            cpuCount: cpu,
            memoryBytes: memoryGiB * gibibyte,
            osDiskBytes: defaultOSDiskBytes,
            dataDiskBytes: kubernetesDataDiskBytes
        )
    }
}
