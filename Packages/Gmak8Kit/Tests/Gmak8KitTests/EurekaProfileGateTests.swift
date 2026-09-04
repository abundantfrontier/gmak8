import Foundation
import Testing

@testable import Gmak8Kit

struct EurekaProfileGateTests {
    private let nestedHost = HostSnapshot(
        processorCount: 12,
        physicalMemoryGiB: 128,
        freeDiskGiB: 200,
        nestedVirtualizationSupported: true
    )

    @Test func kubernetesAndAPIOnlyAlwaysStart() throws {
        var settings = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        try EurekaProfileGate.validateStart(
            settings: settings,
            k3sYAML: K3sConfig.yaml,
            host: nestedHost
        )
        settings.profile = .eurekaAPIOnly
        settings.kubeVirtAddon = true
        try EurekaProfileGate.validateStart(
            settings: settings,
            k3sYAML: "",
            host: HostSnapshot(
                processorCount: 4,
                physicalMemoryGiB: 8,
                freeDiskGiB: 20,
                nestedVirtualizationSupported: false
            )
        )
    }

    @Test func eurekaStartNeedsNestedVirtRAMAndLocalPath() throws {
        var settings = Settings(
            profile: .eureka,
            cpu: 8,
            memoryGiB: 16,
            dataDiskGiB: 256,
            kubeVirtAddon: true
        )
        #expect(throws: ProfileRefusal.nestedVirtualizationUnsupported) {
            try EurekaProfileGate.validateStart(
                settings: settings,
                k3sYAML: K3sConfig.yaml,
                host: HostSnapshot(
                    processorCount: 12,
                    physicalMemoryGiB: 128,
                    freeDiskGiB: 200,
                    nestedVirtualizationSupported: false
                )
            )
        }
        #expect(throws: ProfileRefusal.insufficientMemory(requiredGiB: 18, availableGiB: 8)) {
            try EurekaProfileGate.validateStart(
                settings: settings,
                k3sYAML: K3sConfig.yaml,
                host: HostSnapshot(
                    processorCount: 8,
                    physicalMemoryGiB: 8,
                    freeDiskGiB: 200,
                    nestedVirtualizationSupported: true
                )
            )
        }
        #expect(throws: ProfileRefusal.missingDataDiskLocalPath) {
            try EurekaProfileGate.validateStart(
                settings: settings,
                k3sYAML: "data-dir: /mnt/data/rancher\n",
                host: nestedHost
            )
        }
        settings.disableLocalStorage = true
        #expect(throws: ProfileRefusal.missingDataDiskLocalPath) {
            try EurekaProfileGate.validateStart(
                settings: settings,
                k3sYAML: K3sConfig.yaml,
                host: nestedHost
            )
        }
        settings.disableLocalStorage = false
        try EurekaProfileGate.validateStart(
            settings: settings,
            k3sYAML: K3sConfig.yaml,
            host: nestedHost
        )
    }

    @Test func applyProfileRestampsAcceptedAndKeepsSizesOnRefuse() {
        var settings = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        #expect(settings.applyProfile(.eureka, host: nestedHost) == nil)
        #expect(settings.profile == .eureka)
        #expect(settings.cpu == 8)
        #expect(settings.memoryGiB == 16)
        #expect(settings.dataDiskGiB == 256)
        #expect(settings.kubeVirtAddon)
        #expect(settings.publishL1SSH)

        let small = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 8,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: true
        )
        var api = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        let refusal = api.applyProfile(.eureka, host: small)
        #expect(refusal == .insufficientMemory(requiredGiB: 18, availableGiB: 8))
        #expect(api.profile == .eureka)
        #expect(api.cpu == 4)
        #expect(api.memoryGiB == 6)
        #expect(api.dataDiskGiB == 60)
        #expect(api.applyProfile(.eurekaAPIOnly, host: small) == nil)
        #expect(api.cpu == 4)
        #expect(api.memoryGiB == 4)
        #expect(api.dataDiskGiB == 60)
        #expect(!api.publishL1SSH)
    }

    @Test func missingLocalPathCopyIsHonest() {
        #expect(ProfileRefusal.missingDataDiskLocalPath.onboardingMessage.contains("/mnt/data/local-path"))
        #expect(ProfileRefusal.missingDataDiskLocalPath.errorDescription?.contains("local-storage") == true)
        #expect(OnboardingCopy.useEurekaAPIOnly == "Use Eureka API-only")
        #expect(KubeVirtPin.smokeDiskImage.contains("fedora:40"))
        #expect(KubeVirtPin.smokeInstancetypeKind == "VirtualMachineClusterInstancetype")
        #expect(KubeVirtPin.localDocs == "docs/eureka-local.md")
    }
}
