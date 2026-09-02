import Foundation
import Testing

@testable import Gmak8Kit

struct OnboardingTests {
    @Test func pageCopyMatchesDesign() {
        #expect(OnboardingCopy.welcomeHeadline == "gmak8 runs Kubernetes on this Mac. Not Docker.")
        #expect(OnboardingCopy.localCluster.contains("local Kubernetes cluster"))
        #expect(OnboardingCopy.kubectlContext.contains("gmak8"))
        #expect(OnboardingCopy.menuBarExtra.lowercased().contains("menu bar"))
        #expect(OnboardingCopy.noDockerFootnote.contains("not Docker"))
        #expect(OnboardingCopy.eurekaFootnote.lowercased().contains("optional"))
        #expect(OnboardingCopy.chooseFile == "Choose a file…")
        #expect(OnboardingCopy.eurekaExplanation.contains("stock env.py"))
        #expect(OnboardingCopy.eurekaExplanation.contains("u1.xlarge"))
        #expect(OnboardingCopy.eurekaExplanation.contains("u1.nano"))
        #expect(OnboardingCopy.eurekaExplanation.contains("LoadBalancer"))
        #expect(OnboardingCopy.currentContextCheckbox == "Set gmak8 as kubectl current-context")
        #expect(OnboardingCopy.createAndStart == "Create and start")
        #expect(OnboardingCopy.kubernetesVersionValue == "1.33.3")
        #expect(OnboardingCopy.kubernetesVersionValue == K3sPin.displayVersion)
        #expect(OnboardingCopy.pathExportSnippet == #"export PATH="$HOME/.local/bin:$PATH""#)
        #expect(OnboardingCopy.unsupportedVirtualization.contains("entitlement"))
        #expect(!OnboardingCopy.unsupportedVirtualization.lowercased().contains("lock"))
        #expect(!OnboardingCopy.unsupportedVirtualization.lowercased().contains("another vm"))
        #expect(OnboardingCopy.moveToApplications.contains("/Applications"))
        #expect(OnboardingCopy.noFullDiskAccess.contains("Full Disk Access"))
        #expect(OnboardingCopy.noFullDiskAccess.contains("Accessibility"))
        #expect(OnboardingPage.allCases.count == 7)
        #expect(OnboardingPage.welcome.primaryTitle == OnboardingCopy.continueTitle)
        #expect(OnboardingPage.createCluster.primaryTitle == OnboardingCopy.createAndStart)
        #expect(OnboardingPage.welcome.advanced() == .whatYouGet)
        #expect(OnboardingPage.createCluster.advanced() == .createCluster)
        #expect(OnboardingPage.welcome.back() == .welcome)
    }

    @Test func copyDoesNotPointAtDockerHub() {
        for text in OnboardingCopy.userFacingStrings {
            #expect(!OnboardingCopy.mentionsDockerHub(text), "onboarding copy mentions Docker Hub: \(text)")
        }
        let missing = OnboardingCopy.userFacingAssetError(AirgapError.missingArchive("/tmp/missing.tar"))
        #expect(missing.contains("Choose a file"))
        #expect(!OnboardingCopy.mentionsDockerHub(missing))
        let signed = OnboardingCopy.userFacingAssetError(
            SignedAssetError.missingArchive(label: "guest disk", path: "/tmp/guest.zst")
        )
        #expect(!OnboardingCopy.mentionsDockerHub(signed))
    }

    @Test func currentContextDefaultsOffAndClusterNameIsGmak8() throws {
        let host = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 16,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: false
        )
        let draft = OnboardingDraft(host: host)
        #expect(draft.clusterName == "gmak8")
        #expect(!draft.setCurrentContextOnStart)
        #expect(draft.profile == .kubernetes)
        #expect(draft.cpu == 4)
        #expect(draft.memoryGiB == 6)
        #expect(draft.dataDiskGiB == 60)
        let settings = try draft.makeSettings(host: host)
        #expect(!settings.setCurrentContextOnStart)
        #expect(settings.clusterName == "gmak8")
        #expect(Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60).setCurrentContextOnStart == false)
    }

    @Test func firstRunShowsWhenSettingsFileIsMissing() {
        #expect(FirstRunGate.shouldShowOnboarding(settingsFileExists: false))
        #expect(!FirstRunGate.shouldShowOnboarding(settingsFileExists: true))
    }

    @Test func kubevirtAirgapIsHiddenUnlessEurekaProfile() {
        #expect(OnboardingAssets.visible(for: .kubernetes) == [.guest, .k3sAirgap])
        #expect(!OnboardingAssets.visible(for: .kubernetes).contains(.kubevirtAirgap))
        #expect(OnboardingAssets.visible(for: .eureka).contains(.kubevirtAirgap))
        #expect(OnboardingAssets.visible(for: .eurekaAPIOnly).contains(.kubevirtAirgap))
        #expect(OnboardingAssetKind.guest.isRequired)
        #expect(OnboardingAssetKind.k3sAirgap.isRequired)
        #expect(!OnboardingAssetKind.kubevirtAirgap.isRequired)
        #expect(OnboardingAssetKind.guest.fileName.hasPrefix("gmak8-guest-"))
        #expect(OnboardingAssetKind.k3sAirgap.fileName == AirgapPin.archiveFileName)
    }

    @Test func isSupportedHardFailIsNotALockAndNestedVirtIsInformational() {
        let unsupported = PermissionsProbe.evaluate(
            virtualizationSupported: false,
            nestedVirtualizationSupported: true,
            shouldRefuseLaunchAgent: false
        )
        #expect(unsupported == .unsupportedVirtualization)
        #expect(!unsupported.canContinue)
        let unsupportedMessage = PermissionsProbe.message(unsupported)
        #expect(unsupportedMessage == OnboardingCopy.unsupportedVirtualization)
        #expect(!unsupportedMessage.lowercased().contains("lock"))
        #expect(!unsupportedMessage.lowercased().contains("another vm"))

        let nestedNo = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: false,
            shouldRefuseLaunchAgent: false
        )
        #expect(nestedNo == .ready(nestedVirtualizationSupported: false))
        #expect(nestedNo.canContinue)
        #expect(PermissionsProbe.message(nestedNo) == OnboardingCopy.nestedVirtUnavailable)

        let nestedYes = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: true,
            shouldRefuseLaunchAgent: false
        )
        #expect(nestedYes == .ready(nestedVirtualizationSupported: true))
        #expect(nestedYes.canContinue)
        #expect(PermissionsProbe.message(nestedYes) == OnboardingCopy.nestedVirtAvailable)

        let translocated = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: false,
            shouldRefuseLaunchAgent: true
        )
        #expect(translocated == .translocated)
        #expect(!translocated.canContinue)
        #expect(PermissionsProbe.message(translocated) == OnboardingCopy.moveToApplications)

        #expect(!NestedVirtualizationProbe.isSupported(macOSMajor: 14, platformReportsSupported: true))
        #expect(NestedVirtualizationProbe.isSupported(macOSMajor: 15, platformReportsSupported: true))
        #expect(!NestedVirtualizationProbe.isSupported(macOSMajor: 15, platformReportsSupported: false))
    }

    @Test func assetsAndPermissionsGateCreate() {
        let ready = PermissionsOutcome.ready(nestedVirtualizationSupported: false)
        #expect(
            OnboardingAdvance.canLeave(
                page: .welcome,
                permissions: .unsupportedVirtualization,
                guestReady: false,
                airgapReady: false,
                profileAccepted: true
            )
        )
        #expect(
            !OnboardingAdvance.canLeave(
                page: .assets,
                permissions: ready,
                guestReady: false,
                airgapReady: true,
                profileAccepted: true
            )
        )
        #expect(
            !OnboardingAdvance.canLeave(
                page: .permissions,
                permissions: .unsupportedVirtualization,
                guestReady: true,
                airgapReady: true,
                profileAccepted: true
            )
        )
        #expect(
            !OnboardingAdvance.canLeave(
                page: .permissions,
                permissions: .translocated,
                guestReady: true,
                airgapReady: true,
                profileAccepted: true
            )
        )
        #expect(
            OnboardingAdvance.canLeave(
                page: .permissions,
                permissions: ready,
                guestReady: true,
                airgapReady: true,
                profileAccepted: true
            )
        )
        #expect(
            !OnboardingAdvance.canLeave(
                page: .createCluster,
                permissions: ready,
                guestReady: true,
                airgapReady: true,
                profileAccepted: false
            )
        )
        #expect(
            OnboardingAdvance.canLeave(
                page: .createCluster,
                permissions: ready,
                guestReady: true,
                airgapReady: true,
                profileAccepted: true
            )
        )
    }

    @Test func eurekaRefusalKeepsCreateDisabled() {
        let host = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 8,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: false
        )
        var draft = OnboardingDraft(host: host)
        draft.applyProfile(.eureka, host: host)
        #expect(!draft.profileIsAccepted)
        #expect(draft.profileRefusal == .insufficientMemory(requiredGiB: 18, availableGiB: 8))
        #expect(draft.profileRefusal?.onboardingMessage.contains("Eureka API-only") == true)
        draft.applyProfile(.eurekaAPIOnly, host: host)
        #expect(draft.profileIsAccepted)
        #expect(draft.cpu == 4)
        #expect(draft.memoryGiB == 4)
    }
}
