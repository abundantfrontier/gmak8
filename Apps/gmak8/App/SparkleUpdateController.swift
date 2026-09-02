import AppKit
import Gmak8Kit
import Gmak8XPC
import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    private let keepClusterRunning: () -> Bool

    init(keepClusterRunning: @escaping () -> Bool) {
        self.keepClusterRunning = keepClusterRunning
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyDownloadsUpdates = false
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AppUpdatePendingStart.mark(keepClusterRunningOnQuit: keepClusterRunning())
        let paths = HostPaths.current()
        do {
            try AppUpdateInstall.prepareWillInstall(
                submitPrepareUpdate: {
                    do {
                        try EngineClient.submit(.prepareUpdate, socketURL: paths.engineSocket)
                        return .accepted
                    } catch let error as CLIError where error == .engineNotRunning {
                        return .coreNotRunning
                    }
                },
                wait: {
                    AppUpdateGate.waitUntilCoreReleased(
                        socketURL: paths.engineSocket,
                        lockURLs: paths.diskLockURLs
                    )
                },
                unregisterAgent: {
                    try CoreLaunchAgent.unregister()
                }
            )
        } catch {
            Gmak8Log.ui.error("update prepare failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Update failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            Foundation.exit(1)
        }
    }

    func updaterDidRelaunchApplication(_ updater: SPUUpdater) {
        let bundleURL = Bundle.main.bundleURL
        do {
            _ = try AppUpdateInstall.finishAfterSwap(
                bundleURL: bundleURL,
                keepClusterRunningOnQuit: keepClusterRunning(),
                registerAgent: { url in
                    try CoreLaunchAgent.register(bundleURL: url)
                },
                launchCore: { url in
                    try BundledCoreLauncher.launch(bundleURL: url)
                }
            )
        } catch EngineErrorCode.translocated {
            Gmak8Log.ui.error("update relaunch refused: translocated")
        } catch {
            Gmak8Log.ui.error(
                "update relaunch failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
