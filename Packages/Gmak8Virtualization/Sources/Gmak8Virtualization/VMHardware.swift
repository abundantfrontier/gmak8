public struct VMHardware: Equatable, Sendable {
    public static let gibibyte: UInt64 = 1024 * 1024 * 1024
    public static let defaultOSDiskBytes: UInt64 = 8 * gibibyte

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

    public static let bringUp = VMHardware(
        cpuCount: 2,
        memoryBytes: 2 * gibibyte,
        osDiskBytes: defaultOSDiskBytes,
        dataDiskBytes: defaultOSDiskBytes
    )
}
