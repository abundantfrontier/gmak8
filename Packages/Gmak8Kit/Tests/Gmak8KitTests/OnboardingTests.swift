import Foundation
import Testing

@testable import Gmak8Kit

struct OnboardingTests {
    @Test func pageCopyMatchesDesign() {
        #expect(OnboardingCopy.welcomeHeadline == "gmak8 runs Kubernetes on this Mac.")
        #expect(OnboardingCopy.localCluster.contains("local Kubernetes cluster"))
        #expect(OnboardingCopy.kubectlContext.contains("gmak8"))
        #expect(OnboardingCopy.menuBarExtra.lowercased().contains("menu bar"))
        #expect(OnboardingCopy.eurekaFootnote.lowercased().contains("optional"))
        #expect(OnboardingCopy.chooseFile == "Choose a file…")
        #expect(OnboardingCopy.eurekaExplanation.contains("stock env.py"))
        #expect(OnboardingCopy.eurekaExplanation.contains("u1.xlarge"))
        #expect(OnboardingCopy.eurekaExplanation.contains("u1.nano"))
        #expect(OnboardingCopy.eurekaExplanation.contains("LoadBalancer"))
        #expect(OnboardingCopy.useEurekaAPIOnly == "Use Eureka API-only")
        #expect(OnboardingCopy.eurekaExplanation.contains("docs/eureka-local.md"))
        #expect(OnboardingCopy.currentContextCheckbox == "Set gmak8 as kubectl current-context")
        #expect(OnboardingCopy.createAndStart == "Start cluster")
        #expect(OnboardingCopy.gmak8HelperMissing.contains("Contents/Helpers"))
        #expect(OnboardingCopy.k3sAirgapHint.contains("SHA-256"))
        #expect(OnboardingCopy.k3sAirgapHint.lowercased().contains("container images"))
        #expect(!OnboardingCopy.guestDigestUnpublished.contains(OnboardingCopy.chooseFile))
        #expect(OnboardingCopy.guestLocalFileHint.lowercased().contains("img"))
        #expect(OnboardingCopy.getStartedSection == "Get started")
        #expect(OnboardingCopy.stepK3s.lowercased().contains("container images"))
        #expect(OnboardingCopy.stepGuestWaiting.lowercased().contains("linux disk"))
        #expect(OnboardingCopy.guestHowToBuild.contains("mkosi"))
        #expect(OnboardingCopy.guestHowToBuild.contains("os.img"))
        #expect(OnboardingCopy.guestSection == "Linux disk")
        #expect(OnboardingCopy.k3sSection == "Images")
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
        let pack = OnboardingCopy.userFacingAssetError(GuestOSDiskInstall.Failure.k3sImagePack)
        #expect(pack.lowercased().contains("kubernetes"))
        #expect(pack.lowercased().contains("img") || pack.lowercased().contains("raw"))
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

    @Test func firstRunUsesSetupRailNotABlockingWizard() {
        #expect(!FirstRunGate.shouldShowOnboarding(settingsFileExists: false))
        #expect(!FirstRunGate.shouldShowOnboarding(settingsFileExists: true))
        #expect(FirstRunGate.shouldPersistSettings(needsOnboarding: true))
        #expect(FirstRunGate.shouldPersistSettings(needsOnboarding: false))
        #expect(FirstRunGate.clusterActionsEnabled(needsOnboarding: true))
        #expect(FirstRunGate.clusterActionsEnabled(needsOnboarding: false))
    }

    @Test func kubevirtAirgapRowIsVisibleForEurekaProfiles() {
        #expect(OnboardingAssets.visible(for: .kubernetes) == [.guest, .k3sAirgap])
        #expect(OnboardingAssets.visible(for: .eureka) == [.guest, .k3sAirgap, .kubevirtAirgap])
        #expect(OnboardingAssets.visible(for: .eurekaAPIOnly) == [.guest, .k3sAirgap, .kubevirtAirgap])
        #expect(OnboardingAssets.visible(for: .eureka).contains(.kubevirtAirgap))
        #expect(!OnboardingAssets.isRequiredToContinue(.kubevirtAirgap))
        #expect(!OnboardingAssets.remoteDownloadEnabled(.kubevirtAirgap))
        #expect(OnboardingAssetKind.kubevirtAirgap.fileName.contains("kubevirt"))
        #expect(KubeVirtPin.version == "v1.6.2")
        #expect(KubeVirtPin.cdiVersion == "v1.62.0")
        #expect(KubeVirtPin.instancetypesVersion == "v1.4.0")
        #expect(KubeVirtPin.featureGates == ["VMExport", "EnableVirtioFsConfigVolumes"])
        #expect(KubeVirtPin.smokeInstancetype == "u1.nano")
        #expect(KubeVirtPin.smokeInstancetypeKind == "VirtualMachineClusterInstancetype")
        #expect(KubeVirtPin.smokeDiskImage == "quay.io/containerdisks/fedora:40")
        #expect(VirtctlPin.bundled.fileName == "virtctl")
        #expect(VirtctlPin.bundled.sha256.count == 64)
        #expect(KubeVirtAirgapPin.bundled.signed.hasStubDigest)
        #expect(OnboardingAssetKind.guest.fileName.hasPrefix("gmak8-guest-"))
        #expect(OnboardingAssetKind.k3sAirgap.fileName == AirgapPin.archiveFileName)
        #expect(OnboardingAssetKind.k3sAirgap.title == "Kubernetes images")
        #expect(OnboardingAssetKind.k3sAirgap.defaultSource.contains("GitHub"))
        #expect(OnboardingAssetKind.k3sAirgap.defaultSource.contains("1.33.3"))
        #expect(OnboardingCopy.downloadThisPack == "Download Kubernetes images")
        #expect(OnboardingCopy.useLocalFile.contains("already have"))
        #expect(OnboardingAssets.isRequiredToContinue(.guest))
        #expect(OnboardingAssets.isRequiredToContinue(.k3sAirgap))
        #expect(OnboardingAssets.remoteDownloadEnabled(.guest))
        #expect(OnboardingAssets.remoteDownloadEnabled(.k3sAirgap))
        #expect(OnboardingAssets.chooseFileEnabled(.guest))
        #expect(OnboardingAssets.chooseFileEnabled(.k3sAirgap))
    }

    @Test func isSupportedHardFailIsNotALockAndNestedVirtIsInformational() throws {
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
        #expect(OnboardingCopy.installToApplications == "Install to /Applications")
        #expect(!ApplicationsBundleInstall.isInstalled(at: URL(fileURLWithPath: "/tmp/gmak8.app")))
        #expect(ApplicationsBundleInstall.isInstalled(at: ApplicationsBundleInstall.destination))

        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-install-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "gmak8.app")
        let dest = root.appending(path: "Applications/gmak8.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "ok".write(to: source.appending(path: "Marker"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ApplicationsBundleInstall.install(from: source, to: dest)
        #expect(
            (try? String(contentsOf: dest.appending(path: "Marker"), encoding: .utf8)) == "ok"
        )

        #expect(!NestedVirtualizationProbe.isSupported(macOSMajor: 14, platformReportsSupported: true))
        #expect(NestedVirtualizationProbe.isSupported(macOSMajor: 15, platformReportsSupported: true))
        #expect(!NestedVirtualizationProbe.isSupported(macOSMajor: 15, platformReportsSupported: false))
        #expect(NestedVirtualizationProbe.isSupported(macOSMajor: 16, platformReportsSupported: true))
        #expect(!NestedVirtualizationProbe.isSupported(macOSMajor: 14, platformReportsSupported: false))
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
            OnboardingAdvance.canLeave(
                page: .assets,
                permissions: ready,
                guestReady: false,
                airgapReady: true,
                profileAccepted: true,
                guestRequired: false,
                airgapRequired: true
            )
        )
        #expect(
            OnboardingAdvance.canLeave(
                page: .createCluster,
                permissions: ready,
                guestReady: false,
                airgapReady: true,
                profileAccepted: true,
                guestRequired: false,
                airgapRequired: true
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
        #expect(draft.cpu == 4)
        #expect(draft.memoryGiB == 4)
        #expect(draft.dataDiskGiB == 60)
        draft.applyProfile(.eurekaAPIOnly, host: host)
        #expect(draft.profileIsAccepted)
        #expect(draft.cpu == 4)
        #expect(draft.memoryGiB == 4)
    }

    @Test func remoteDownloadOnlyForGmak8SignedReleaseWithRealDigest() {
        let stub = SignedAssetPin(
            fileName: GuestAssetPin.archiveFileName,
            url: URL(
                string:
                    "https://github.com/abundantfrontier/gmak8/releases/download/v0.0.1/\(GuestAssetPin.archiveFileName)"
            )!,
            sha256: "0000000000000000000000000000000000000000000000000000000000000000",
            maxBytes: GuestAssetPin.maxCompressedBytes
        )
        #expect(stub.hasStubDigest)
        #expect(!stub.remoteDownloadEnabled)
        #expect(!stub.chooseFileEnabled)
        #expect(GuestAssetPin.bundled.signed.remoteDownloadEnabled)
        #expect(AirgapPin.bundled.signed.remoteDownloadEnabled)
        let published = SignedAssetPin(
            fileName: AirgapPin.archiveFileName,
            url: URL(
                string:
                    "https://github.com/abundantfrontier/gmak8/releases/download/v0.0.1/\(AirgapPin.archiveFileName)")!,
            sha256: AirgapPin.bundled.sha256,
            maxBytes: AirgapPin.maxCompressedBytes
        )
        #expect(!published.hasStubDigest)
        #expect(published.chooseFileEnabled)
        #expect(published.remoteDownloadEnabled)
        let k3sIO = AirgapPin.bundled.signed
        #expect(!SignedAssetPin.isGmak8SignedReleaseURL(k3sIO.url))
    }

    @Test func engineReadyPollSucceedsOnLaterAttempt() {
        var calls = 0
        #expect(
            EngineReadyPoll.wait(attempts: 3) {
                calls += 1
                return calls >= 2
            }
        )
        #expect(calls == 2)
        #expect(!EngineReadyPoll.wait(attempts: 2, isReady: { false }))
    }
}
