public enum Profile: String, Codable, Equatable, Sendable, CaseIterable {
    case kubernetes
    case eureka
    case eurekaAPIOnly
}

public struct HostSnapshot: Equatable, Sendable {
    public var processorCount: Int
    public var physicalMemoryGiB: Int
    public var freeDiskGiB: Int
    public var nestedVirtualizationSupported: Bool

    public init(
        processorCount: Int,
        physicalMemoryGiB: Int,
        freeDiskGiB: Int,
        nestedVirtualizationSupported: Bool
    ) {
        self.processorCount = processorCount
        self.physicalMemoryGiB = physicalMemoryGiB
        self.freeDiskGiB = freeDiskGiB
        self.nestedVirtualizationSupported = nestedVirtualizationSupported
    }
}

public struct ProfileResources: Equatable, Sendable {
    public var cpu: Int
    public var memoryGiB: Int
    public var dataDiskGiB: Int
    public var kubeVirtPack: Bool
    public var nestedVirt: Bool

    public init(cpu: Int, memoryGiB: Int, dataDiskGiB: Int, kubeVirtPack: Bool, nestedVirt: Bool) {
        self.cpu = cpu
        self.memoryGiB = memoryGiB
        self.dataDiskGiB = dataDiskGiB
        self.kubeVirtPack = kubeVirtPack
        self.nestedVirt = nestedVirt
    }
}

public enum ProfileRefusal: Error, Equatable, Sendable {
    case insufficientMemory(requiredGiB: Int, availableGiB: Int)
    case insufficientDisk(requiredGiB: Int, availableGiB: Int)
    case nestedVirtualizationUnsupported
}

public enum ProfileResolution: Equatable, Sendable {
    case accepted(ProfileResources)
    case refused(ProfileRefusal)
}

extension Profile {
    public func resourceDefaults(host: HostSnapshot) -> ProfileResolution {
        switch self {
        case .kubernetes:
            return .accepted(
                ProfileResources(
                    cpu: Self.cappedHostMinusTwo(cap: 4, hostProcessorCount: host.processorCount),
                    memoryGiB: host.physicalMemoryGiB >= 16 ? 6 : 4,
                    dataDiskGiB: 60,
                    kubeVirtPack: false,
                    nestedVirt: false
                )
            )
        case .eureka:
            if host.physicalMemoryGiB < 18 {
                return .refused(
                    .insufficientMemory(requiredGiB: 18, availableGiB: host.physicalMemoryGiB)
                )
            }
            if host.freeDiskGiB < 80 {
                return .refused(
                    .insufficientDisk(requiredGiB: 80, availableGiB: host.freeDiskGiB)
                )
            }
            if !host.nestedVirtualizationSupported {
                return .refused(.nestedVirtualizationUnsupported)
            }
            return .accepted(
                ProfileResources(
                    cpu: Self.cappedHostMinusTwo(cap: 8, hostProcessorCount: host.processorCount),
                    memoryGiB: host.physicalMemoryGiB >= 24 ? 16 : 12,
                    dataDiskGiB: 256,
                    kubeVirtPack: true,
                    nestedVirt: true
                )
            )
        case .eurekaAPIOnly:
            return .accepted(
                ProfileResources(
                    cpu: 4,
                    memoryGiB: 4,
                    dataDiskGiB: 60,
                    kubeVirtPack: true,
                    nestedVirt: false
                )
            )
        }
    }

    private static func cappedHostMinusTwo(cap: Int, hostProcessorCount: Int) -> Int {
        min(cap, max(1, hostProcessorCount - 2))
    }
}
