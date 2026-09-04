import Gmak8Kit
import Gmak8Kubernetes
import Gmak8XPC
import Testing

struct Gmak8AppTests {
    @Test func kitVersionIsPinned() {
        #expect(Gmak8Kit.version == "0.0.1")
    }

    @Test func updateCopyWarnsThatClusterRestarts() {
        #expect(AppUpdateCopy.checkForUpdates == "Check for Updates…")
        #expect(AppUpdateCopy.restartsCluster == "Updates restart the cluster.")
        #expect(AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: true))
        #expect(!AppUpdatePolicy.shouldStartAfterSwap(keepClusterRunningOnQuit: false))
        #expect(AppUpdatePolicy.duringSwap().agent == .unregister)
        #expect(AppUpdatePolicy.duringSwap().extra == .keep)
        #expect(AppUpdatePolicy.waitTimeout == 60)
    }

    @Test func iconMapsEachClusterState() {
        #expect(MenuBarIconAppearance(state: .stopped) == .grayStopped)
        #expect(MenuBarIconAppearance(state: .stopping) == .grayStopped)
        #expect(MenuBarIconAppearance(state: .starting) == .blueStarting)
        #expect(MenuBarIconAppearance(state: .running) == .filledRunning)
        #expect(MenuBarIconAppearance(state: .degraded) == .yellowDegraded)
        #expect(MenuBarIconAppearance(state: .failed) == .redFailed)
        #expect(MenuBarIconAppearance(state: .paused) == .paused)
        #expect(MenuBarIconAppearance(state: .stopped).systemImage == "circle")
        #expect(MenuBarIconAppearance(state: .starting).systemImage == "circle.dotted")
        #expect(MenuBarIconAppearance(state: .running).systemImage == "circle.fill")
        #expect(MenuBarIconAppearance(state: .degraded).systemImage == "exclamationmark.triangle.fill")
        #expect(MenuBarIconAppearance(state: .failed).systemImage == "xmark.octagon.fill")
        #expect(MenuBarIconAppearance(state: .paused).systemImage == "pause.circle.fill")
        #expect(MenuBarIconAppearance(state: .paused).showsPauseBadge)
        #expect(!MenuBarIconAppearance(state: .running).showsPauseBadge)
        let symbols = Set(MenuBarIconAppearance.allCases.map(\.systemImage))
        #expect(symbols.count == MenuBarIconAppearance.allCases.count)
    }

    @Test func closeLastWindowDoesNotQuitExtra() {
        let keep = QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: true)
        let stop = QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: true)
        let keepAction = keep.action(for: .closeLastWindow)
        let stopAction = stop.action(for: .closeLastWindow)
        #expect(keepAction == .becomeAccessory(stopCluster: false))
        #expect(stopAction == .becomeAccessory(stopCluster: true))
        #expect(keepAction.extraRemains)
        #expect(stopAction.extraRemains)
        #expect(!keepAction.isHeadless)
        #expect(!stopAction.isHeadless)
    }

    @Test func firstQuitSheetDefaultFollowsKeepRunningSetting() {
        let keep = QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: false)
        let stop = QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: false)
        #expect(keep.action(for: .quitRequested) == .showFirstQuitSheet(defaultKeepRunning: true))
        #expect(stop.action(for: .quitRequested) == .showFirstQuitSheet(defaultKeepRunning: false))
        #expect(FirstQuitPrompt.defaultKeepRunning(keepClusterRunningOnQuit: true))
        #expect(!FirstQuitPrompt.defaultKeepRunning(keepClusterRunningOnQuit: false))
        #expect(
            FirstQuitPrompt.message
                == "Keep cluster running in the background? The menu bar extra will stay."
        )
        #expect(FirstQuitPrompt.keepRunningChosen(firstButton: true, defaultKeepRunning: true))
        #expect(!FirstQuitPrompt.keepRunningChosen(firstButton: false, defaultKeepRunning: true))
        #expect(!FirstQuitPrompt.keepRunningChosen(firstButton: true, defaultKeepRunning: false))
        #expect(FirstQuitPrompt.keepRunningChosen(firstButton: false, defaultKeepRunning: false))
    }

    @Test func choosingNotToKeepRunningStopsThenQuits() {
        let policy = QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: false)
        let result = policy.applyingSheetChoice(false)
        #expect(result.action == .stopClusterThenTerminate)
        #expect(!result.action.extraRemains)
        #expect(!result.action.clusterStays)
        #expect(!result.action.isHeadless)
        #expect(!result.policy.keepClusterRunningOnQuit)
        #expect(result.policy.hasAskedFirstQuit)
    }

    @Test func keepingRunningLeavesExtra() {
        let policy = QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: false)
        let result = policy.applyingSheetChoice(true)
        #expect(result.action == .hideWindowsKeepExtra)
        #expect(result.action.extraRemains)
        #expect(result.action.clusterStays)
        #expect(!result.action.isHeadless)
        #expect(result.policy.keepClusterRunningOnQuit)
    }

    @Test func subsequentQuitHonorsKeepRunningByRefusingHeadless() {
        let keep = QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: true)
        let stop = QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: true)
        #expect(keep.action(for: .quitRequested) == .refuseHeadlessKeepExtra)
        #expect(keep.action(for: .quitRequested).extraRemains)
        #expect(stop.action(for: .quitRequested) == .stopClusterThenTerminate)
        #expect(keep.action(for: .stopAndQuit) == .stopClusterThenTerminate)
    }

    @Test func headlessClusterWithoutExtraIsRefused() {
        #expect(QuitPolicy.isHeadless(clusterStays: true, extraRemains: false))
        #expect(!QuitPolicy.isHeadless(clusterStays: true, extraRemains: true))
        #expect(!QuitPolicy.isHeadless(clusterStays: false, extraRemains: false))

        let policies = [
            QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: false),
            QuitPolicy(keepClusterRunningOnQuit: true, hasAskedFirstQuit: true),
            QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: false),
            QuitPolicy(keepClusterRunningOnQuit: false, hasAskedFirstQuit: true),
        ]
        let intents: [QuitIntent] = [.closeLastWindow, .quitRequested, .stopAndQuit]
        for policy in policies {
            for intent in intents {
                let action = policy.action(for: intent)
                #expect(!action.isHeadless)
                if case .showFirstQuitSheet = action {
                    #expect(!policy.applyingSheetChoice(true).action.isHeadless)
                    #expect(!policy.applyingSheetChoice(false).action.isHeadless)
                    #expect(policy.applyingSheetChoice(true).action.extraRemains)
                }
            }
        }
    }

    @Test func terminalScriptExportsQuotedKubeconfig() {
        let path = "/Users/test/Library/Application Support/dev.gmak8.app/kubeconfig"
        let source = TerminalLauncher.appleScriptSource(kubeconfigPath: path)
        #expect(source.contains("tell application \"Terminal\""))
        #expect(source.contains("export KUBECONFIG='\(path)'"))
        let mkosi = TerminalLauncher.appleScriptSource(workingDirectory: "/tmp/guest/mkosi")
        #expect(mkosi.contains("cd '/tmp/guest/mkosi'"))
        #expect(mkosi.contains("mkosi"))
        #expect(TerminalLauncher.shellQuoted("a'b") == "'a'\\''b'")
        #expect(TerminalLauncher.terminalBundleIdentifier == "com.apple.Terminal")
        let exec = TerminalLauncher.execCommand(
            kubeconfigPath: path,
            namespace: "kube-system",
            pod: "coredns",
            container: "coredns"
        )
        #expect(exec.contains("kubectl exec -it"))
        #expect(exec.contains("-- '/bin/sh'"))
        #expect(exec.contains("-- '/bin/bash'"))
        #expect(exec.contains("-c 'coredns'"))
        #expect(exec.contains(WorkloadsCopy.noShell))
        #expect(exec.contains(WorkloadsCopy.podNotRunning))
        #expect(exec.contains("jsonpath='{.status.phase}'"))
        #expect(WorkloadsCopy.noShell.contains("distroless"))
        #expect(WorkloadsCopy.podNotRunning.contains("not running"))
        let forward = TerminalLauncher.portForwardCommand(
            kubeconfigPath: path,
            namespace: "default",
            pod: "app",
            local: 18080,
            remote: 8080
        )
        #expect(forward.contains("--address 127.0.0.1"))
        #expect(forward.contains("18080:8080"))
        #expect(!forward.contains("0.0.0.0"))
    }

    @Test func lostEngineConnectionResetsStatusToStopped() {
        #expect(CLIError.engineNotRunning.resetsClusterStatus)
        #expect(CLIError.communicationFailed.resetsClusterStatus)
        #expect(CLIError.invalidReply.resetsClusterStatus)
        #expect(!CLIError.engineError(.conflict).resetsClusterStatus)
        let disconnected = EngineStatusAfterDisconnect.status()
        #expect(disconnected.state == .stopped)
        #expect(MenuBarIconAppearance(state: disconnected.state) == .grayStopped)
    }

    @Test func productWindowIdentityIgnoresSettingsAndStatusBar() {
        #expect(
            ProductWindowIdentity.isProductWindow(
                identifier: ProductWindowIdentity.sceneID,
                title: "gmak8",
                isStatusBar: false
            )
        )
        #expect(
            ProductWindowIdentity.isProductWindow(identifier: nil, title: "gmak8", isStatusBar: false)
        )
        #expect(
            !ProductWindowIdentity.isProductWindow(
                identifier: "com.apple.SwiftUI.Settings",
                title: "gmak8",
                isStatusBar: false
            )
        )
        #expect(
            !ProductWindowIdentity.isProductWindow(identifier: nil, title: "Settings", isStatusBar: false)
        )
        #expect(
            !ProductWindowIdentity.isProductWindow(
                identifier: ProductWindowIdentity.sceneID,
                title: "gmak8",
                isStatusBar: true
            )
        )
        #expect(ProductWindowIdentity.shouldHideWhenKeepingExtra(isStatusBar: false))
        #expect(!ProductWindowIdentity.shouldHideWhenKeepingExtra(isStatusBar: true))
    }

    @Test func statusPresentationFormatsPinAndMetrics() {
        #expect(StatusPresentation.shortK3sVersion() == "1.33.3")
        #expect(StatusPresentation.productLine() == "gmak8 · k3s 1.33.3 · KubeVirt 1.6.2")
        #expect(StatusPresentation.productLine(includeKubeVirt: false) == "gmak8 · k3s 1.33.3")
        #expect(StatusPresentation.nestedVirtLine(true) == "Nested virt: Yes")
        #expect(StatusPresentation.nestedVirtLine(false) == "Nested virt: No")
        #expect(StatusPresentation.cpuPercent(0.08) == 8)
        #expect(StatusPresentation.cpuPercent(8) == 8)
        let metrics = VMMetrics(cpu: 0.08, ramUsed: 4.1, ramCap: 16, diskUsed: 40, diskCap: 256)
        #expect(
            StatusPresentation.metricsLine(metrics)
                == "CPU 8%   RAM 4.1 / 16 GiB   Disk 40 / 256 GiB"
        )
    }

    @Test func onboardingCopyCurrentContextAndPermissions() {
        #expect(OnboardingCopy.welcomeHeadline == "gmak8 runs Kubernetes on this Mac.")
        #expect(OnboardingCopy.currentContextCheckbox == "Set gmak8 as kubectl current-context")
        #expect(OnboardingCopy.createAndStart == "Start cluster")
        #expect(OnboardingCopy.kubernetesVersionValue == "1.33.3")
        #expect(OnboardingCopy.pathExportSnippet == #"export PATH="$HOME/.local/bin:$PATH""#)
        let host = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 16,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: false
        )
        #expect(!OnboardingDraft(host: host).setCurrentContextOnStart)
        #expect(!OnboardingCopy.unsupportedVirtualization.lowercased().contains("lock"))
        for text in OnboardingCopy.userFacingStrings {
            #expect(!OnboardingCopy.mentionsDockerHub(text))
        }
        let nested = PermissionsProbe.evaluate(
            virtualizationSupported: true,
            nestedVirtualizationSupported: false,
            shouldRefuseLaunchAgent: false
        )
        #expect(nested.canContinue)
        let unsupported = PermissionsProbe.evaluate(
            virtualizationSupported: false,
            nestedVirtualizationSupported: false,
            shouldRefuseLaunchAgent: false
        )
        #expect(!unsupported.canContinue)
        #expect(CoreLaunchAgent.twoLoginItemsExplanation.contains("two Login Items"))
        #expect(FirstRunGate.shouldPersistSettings(needsOnboarding: true))
        #expect(FirstRunGate.clusterActionsEnabled(needsOnboarding: true))
        #expect(!GuestAssetPin.bundled.signed.hasStubDigest)
        #expect(GuestAssetPin.bundled.signed.remoteDownloadEnabled)
        #expect(GuestAssetPin.bundled.signed.chooseFileEnabled)
        #expect(OnboardingAssets.chooseFileEnabled(.guest))
        #expect(AirgapPin.bundled.signed.remoteDownloadEnabled)
        #expect(AirgapPin.bundled.signed.chooseFileEnabled)
        #expect(!OnboardingCopy.guestDigestUnpublished.contains(OnboardingCopy.chooseFile))
    }

    @Test func clusterOverviewSidebarAndCardsMatchDesign() {
        #expect(
            ClusterSidebarItem.allCases.map(\.title) == [
                ClusterOverviewCopy.cluster,
                ClusterOverviewCopy.workloads,
                ClusterOverviewCopy.kubeVirt,
                ClusterOverviewCopy.images,
                ClusterOverviewCopy.diagnostics,
            ])
        #expect(!ClusterSidebarItem.visible(for: .kubernetes).contains(.kubeVirt))
        #expect(ClusterSidebarItem.visible(for: .eureka).contains(.kubeVirt))
        #expect(ClusterSidebarItem.visible(for: .kubernetes, kubeVirtEnabled: true).contains(.kubeVirt))
        #expect(KubeVirtCopy.nestedVirtUnsupported.contains("Pending"))
        #expect(!KubeVirtCopy.empty.lowercased().contains("nginx"))
        #expect(!KubeVirtCopy.nestedVirtUnsupported.lowercased().contains("ssh"))
        #expect(!KubeVirtCopy.nestedVirtUnsupported.lowercased().contains("ood"))
        #expect(KubeVirtKind.allCases.first == .virtualMachine)
        #expect(ClusterOverviewCopy.sqlite == "SQLite")
        #expect(ClusterOverviewCopy.readyz == "/readyz")
        #expect(ClusterOverview.sampleRunning().addons.map(\.name) == ClusterAddonMatcher.kubernetesAddons)
        #expect(WorkloadsCopy.empty.contains("Apply a manifest"))
        #expect(!WorkloadsCopy.empty.lowercased().contains("nginx"))
        #expect(WorkloadKind.allCases.first == .pod)
        #expect(ImagesCopy.empty.contains("Load an OCI"))
        #expect(ImagesCopy.guestMissingImages.contains("/images"))
        #expect(ImagesCopy.guestMissingImages == NodeImageErrors.guestMissingImages)
        #expect(ClusterOverviewCopy.imagesEmpty == ImagesCopy.empty)
        #expect(SystemImageMatcher.isSystem(refs: ["docker.io/rancher/mirrored-pause:3.6"]))
        #expect(!SystemImageMatcher.isSystem(refs: ["nginx:dev"]))
        #expect(SettingsCopy.balloonUnsupported.contains("not supported"))
        #expect(SettingsCopy.virtctlHelp.contains("virtctl"))
        #expect(OnboardingCopy.useEurekaAPIOnly.contains("API-only"))
        #expect(OnboardingCopy.eurekaExplanation.contains("docs/eureka-local.md"))
        #expect(SettingsCopy.telemetryOff.contains("Docker Hub"))
        #expect(HostUserIdentity.warning.contains("501") || HostUserIdentity.warning.contains("runAsUser"))
        #expect(ClusterOverviewCopy.kvmPresent.contains("/dev/kvm"))
        #expect(ClusterOverviewCopy.kvmMissing.contains("not present"))
        #expect(StatusPresentation.nestedVirtLine(true) == "Nested virt: Yes")
    }

    @Test func recoveryCopiesMatchLockedDiskAndTranslocation() {
        #expect(RecoveryCopy.diskImagesLocked.contains("data.img"))
        #expect(RecoveryCopy.diskImagesLocked.contains("engine.sock"))
        #expect(RecoveryCopy.translocated == "Move gmak8 to /Applications and re-open.")
        #expect(ResetConfirmation.engineRequest == .reset(force: true))
        #expect(!RecoveryAction.allCases.map(\.rawValue).contains { $0.lowercased().contains("snapshot") })
    }

    @Test func restartStartsAfterStopNotInsteadOfStart() {
        #expect(ClusterRestart.shouldStart(pending: true, state: .stopped))
        #expect(ClusterRestart.shouldStart(pending: true, state: .failed))
        #expect(!ClusterRestart.shouldStart(pending: true, state: .running))
        #expect(!ClusterRestart.shouldStart(pending: true, state: .degraded))
        #expect(!ClusterRestart.shouldStart(pending: true, state: .stopping))
        #expect(!ClusterRestart.shouldStart(pending: false, state: .stopped))
    }

    @Test func explicitStopCancelsPendingRestart() {
        let pendingRestart = ClusterRestart.pending(after: .restart)
        #expect(pendingRestart)
        #expect(ClusterRestart.shouldStart(pending: pendingRestart, state: .stopped))
        let afterStop = ClusterRestart.pending(after: .stop)
        #expect(!afterStop)
        #expect(!ClusterRestart.shouldStart(pending: afterStop, state: .stopped))
        #expect(!ClusterRestart.shouldStart(pending: afterStop, state: .failed))
    }

    @Test func recoveryWindowHoldsResetSheetNotMenuExtra() {
        #expect(
            ProductWindowIdentity.isRecoveryWindow(
                identifier: ProductWindowIdentity.recoverySceneID,
                title: "Recovery",
                isStatusBar: false
            )
        )
        #expect(
            !ProductWindowIdentity.isProductWindow(
                identifier: ProductWindowIdentity.recoverySceneID,
                title: "Recovery",
                isStatusBar: false
            )
        )
        #expect(
            ProductWindowIdentity.isResetSheetHost(
                identifier: ProductWindowIdentity.recoverySceneID,
                title: "Recovery",
                isStatusBar: false,
                isPanel: false
            )
        )
        #expect(
            ProductWindowIdentity.isResetSheetHost(
                identifier: ProductWindowIdentity.sceneID,
                title: "gmak8",
                isStatusBar: false,
                isPanel: false
            )
        )
        #expect(
            !ProductWindowIdentity.isResetSheetHost(
                identifier: ProductWindowIdentity.sceneID,
                title: "gmak8",
                isStatusBar: false,
                isPanel: true
            )
        )
        #expect(
            !ProductWindowIdentity.isResetSheetHost(
                identifier: nil,
                title: "Item-0",
                isStatusBar: false,
                isPanel: true
            )
        )
    }

    @Test func unimplementedRecoveryActionsAreDisabled() {
        #expect(!RecoveryAction.pruneImages.isAvailable)
        #expect(!RecoveryAction.switchAPIPort16443.isAvailable)
        #expect(!RecoveryAction.pickAPIPort.isAvailable)
        #expect(!RecoveryAction.pickIngressHostPorts.isAvailable)
        #expect(!RecoveryAction.skipNodePort.isAvailable)
        #expect(!RecoveryAction.remapNodePort.isAvailable)
        #expect(!RecoveryAction.showK3sJournal.isAvailable)
        #expect(RecoveryAction.showLsof.isAvailable)
        #expect(RecoveryAction.showSerial.isAvailable)
        #expect(RecoveryAction.reset.isAvailable)
        #expect(RecoveryAction.restartVM.isAvailable)
    }
}
