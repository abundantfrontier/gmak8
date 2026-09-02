import Gmak8Kit
import Gmak8XPC
import Testing

struct Gmak8AppTests {
    @Test func kitVersionIsPinned() {
        #expect(Gmak8Kit.version == "0.0.1")
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
        #expect(MenuBarIconAppearance(state: .starting).systemImage == "circle")
        #expect(MenuBarIconAppearance(state: .running).systemImage == "circle.fill")
        #expect(MenuBarIconAppearance(state: .degraded).systemImage == "circle.fill")
        #expect(MenuBarIconAppearance(state: .failed).systemImage == "circle.fill")
        #expect(MenuBarIconAppearance(state: .paused).systemImage == "pause.circle.fill")
        #expect(MenuBarIconAppearance(state: .paused).showsPauseBadge)
        #expect(!MenuBarIconAppearance(state: .running).showsPauseBadge)
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
        #expect(TerminalLauncher.shellQuoted("a'b") == "'a'\\''b'")
        #expect(TerminalLauncher.terminalBundleIdentifier == "com.apple.Terminal")
    }

    @Test func statusPresentationFormatsPinAndMetrics() {
        #expect(StatusPresentation.shortK3sVersion() == "1.33.3")
        #expect(StatusPresentation.productLine() == "gmak8 · k3s 1.33.3 · KubeVirt 1.6.1")
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
}
