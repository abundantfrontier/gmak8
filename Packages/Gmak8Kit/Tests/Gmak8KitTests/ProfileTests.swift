import Testing

@testable import Gmak8Kit

struct ProfileTests {
    struct ResourceCase: Sendable, CustomTestStringConvertible {
        let name: String
        let profile: Profile
        let host: HostSnapshot
        let expected: ProfileResolution

        var testDescription: String { name }
    }

    @Test(arguments: [
        ResourceCase(
            name: "kubernetes 16 GiB 8 CPU",
            profile: .kubernetes,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 16,
                freeDiskGiB: 100,
                nestedVirtualizationSupported: false
            ),
            expected: .accepted(
                ProfileResources(cpu: 4, memoryGiB: 6, dataDiskGiB: 60, kubeVirtPack: false, nestedVirt: false)
            )
        ),
        ResourceCase(
            name: "kubernetes 15 GiB leaves 4 GiB RAM",
            profile: .kubernetes,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 15,
                freeDiskGiB: 100,
                nestedVirtualizationSupported: false
            ),
            expected: .accepted(
                ProfileResources(cpu: 4, memoryGiB: 4, dataDiskGiB: 60, kubeVirtPack: false, nestedVirt: false)
            )
        ),
        ResourceCase(
            name: "kubernetes 4 CPU uses host-2",
            profile: .kubernetes,
            host: HostSnapshot(
                processorCount: 4,
                physicalMemoryGiB: 16,
                freeDiskGiB: 100,
                nestedVirtualizationSupported: false
            ),
            expected: .accepted(
                ProfileResources(cpu: 2, memoryGiB: 6, dataDiskGiB: 60, kubeVirtPack: false, nestedVirt: false)
            )
        ),
        ResourceCase(
            name: "eureka 24 GiB nested",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 12,
                physicalMemoryGiB: 24,
                freeDiskGiB: 200,
                nestedVirtualizationSupported: true
            ),
            expected: .accepted(
                ProfileResources(cpu: 8, memoryGiB: 16, dataDiskGiB: 256, kubeVirtPack: true, nestedVirt: true)
            )
        ),
        ResourceCase(
            name: "eureka 18 GiB nested",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 18,
                freeDiskGiB: 80,
                nestedVirtualizationSupported: true
            ),
            expected: .accepted(
                ProfileResources(cpu: 6, memoryGiB: 12, dataDiskGiB: 256, kubeVirtPack: true, nestedVirt: true)
            )
        ),
        ResourceCase(
            name: "eureka 23 GiB is 12 GiB RAM",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 10,
                physicalMemoryGiB: 23,
                freeDiskGiB: 80,
                nestedVirtualizationSupported: true
            ),
            expected: .accepted(
                ProfileResources(cpu: 8, memoryGiB: 12, dataDiskGiB: 256, kubeVirtPack: true, nestedVirt: true)
            )
        ),
        ResourceCase(
            name: "eureka refuses below 18 GiB RAM",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 17,
                freeDiskGiB: 200,
                nestedVirtualizationSupported: true
            ),
            expected: .refused(.insufficientMemory(requiredGiB: 18, availableGiB: 17))
        ),
        ResourceCase(
            name: "eureka refuses below 80 GiB disk",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 18,
                freeDiskGiB: 79,
                nestedVirtualizationSupported: true
            ),
            expected: .refused(.insufficientDisk(requiredGiB: 80, availableGiB: 79))
        ),
        ResourceCase(
            name: "eureka refuses without nested virt",
            profile: .eureka,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 24,
                freeDiskGiB: 200,
                nestedVirtualizationSupported: false
            ),
            expected: .refused(.nestedVirtualizationUnsupported)
        ),
        ResourceCase(
            name: "eurekaAPIOnly tiny defaults",
            profile: .eurekaAPIOnly,
            host: HostSnapshot(
                processorCount: 8,
                physicalMemoryGiB: 8,
                freeDiskGiB: 20,
                nestedVirtualizationSupported: false
            ),
            expected: .accepted(
                ProfileResources(cpu: 4, memoryGiB: 4, dataDiskGiB: 60, kubeVirtPack: true, nestedVirt: false)
            )
        ),
    ])
    func resourceDefaults(_ c: ResourceCase) {
        #expect(c.profile.resourceDefaults(host: c.host) == c.expected)
    }

    @Test func profileRawValuesMatchDesign() {
        #expect(Profile.kubernetes.rawValue == "kubernetes")
        #expect(Profile.eureka.rawValue == "eureka")
        #expect(Profile.eurekaAPIOnly.rawValue == "eurekaAPIOnly")
        #expect(Profile.allCases.count == 3)
        #expect(Profile.kubernetes.displayName == "Kubernetes")
        #expect(Profile.eureka.displayName == "Eureka")
        #expect(Profile.eurekaAPIOnly.displayName == "Eureka API-only")
    }
}
