import AppKit
import Gmak8Kit
import Gmak8XPC
@preconcurrency import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, SPUUpdaterDelegate {
    private let userDriver: Gmak8SparkleUserDriver
    private var updater: SPUUpdater!
    private let keepClusterRunning: () -> Bool

    init(keepClusterRunning: @escaping () -> Bool) {
        self.keepClusterRunning = keepClusterRunning
        userDriver = Gmak8SparkleUserDriver(hostBundle: .main)
        super.init()
        userDriver.interceptInstall = { [weak self] reply in
            self?.prepareThenReply(reply)
        }
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self
        )
        updater.automaticallyDownloadsUpdates = false
        do {
            try updater.start()
        } catch {
            Gmak8Log.ui.error("Sparkle failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func completePostSwap(startCluster: @escaping () -> Void) {
        let bundleURL = Bundle.main.bundleURL
        let socketURL = HostPaths.current().engineSocket
        Task { @MainActor in
            do {
                try CoreLaunchAgent.register(bundleURL: bundleURL)
                let live = await Task.detached {
                    AppUpdateGate.waitUntilCoreLive(socketURL: socketURL)
                }.value
                if !live {
                    try BundledCoreLauncher.launch(bundleURL: bundleURL)
                }
            } catch EngineErrorCode.translocated {
                Gmak8Log.ui.error("update relaunch refused: translocated")
            } catch {
                Gmak8Log.ui.error(
                    "update relaunch failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            startCluster()
        }
    }

    /// Sparkle 2 postpone cannot send `SPUCancelInstallation`; prepare happens before `Install`.
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        false
    }

    private var pendingInstallReply: ((SPUUserUpdateChoice) -> Void)?

    private func prepareThenReply(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
        pendingInstallReply = reply
        let keepRunning = keepClusterRunning()
        let paths = HostPaths.current()
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Self.waitForCoreExit(paths: paths)
            DispatchQueue.main.async {
                self.finishPrepare(outcome, keepRunning: keepRunning)
            }
        }
    }

    private nonisolated static func waitForCoreExit(paths: HostPaths) -> AppUpdatePrepareResult {
        AppUpdateInstall.waitForCoreExit(
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
            }
        )
    }

    private func finishPrepare(_ outcome: AppUpdatePrepareResult, keepRunning: Bool) {
        let reply = pendingInstallReply
        pendingInstallReply = nil
        switch outcome {
        case .ready:
            do {
                try CoreLaunchAgent.unregister()
                AppUpdatePendingStart.mark(keepClusterRunningOnQuit: keepRunning)
                reply?(.install)
            } catch {
                AppUpdatePendingStart.clear()
                reply?(.skip)
                failPrepare(outcome, error: error)
            }
        case .submitFailed:
            AppUpdatePendingStart.clear()
            reply?(.skip)
            failPrepare(outcome, error: AppUpdateError.submitFailed)
        case .waitTimeout:
            AppUpdatePendingStart.clear()
            reply?(.skip)
            failPrepare(outcome, error: AppUpdateError.timeoutWaitingForCore)
        }
    }

    private func failPrepare(_ outcome: AppUpdatePrepareResult, error: any Error) {
        Gmak8Log.ui.error("update prepare failed: \(error.localizedDescription, privacy: .public)")
        let socketURL = HostPaths.current().engineSocket
        let socketLive = EngineSocketProbe.isLive(socketURL)
        if AppUpdateInstall.shouldRestoreCore(after: outcome, socketLive: socketLive) {
            restoreCoreAndAlert(error)
            return
        }
        presentUpdateFailure(error)
    }

    private func restoreCoreAndAlert(_ error: any Error) {
        let bundleURL = Bundle.main.bundleURL
        let socketURL = HostPaths.current().engineSocket
        Task { @MainActor in
            do {
                try CoreLaunchAgent.unregister()
                try CoreLaunchAgent.register(bundleURL: bundleURL)
                let live = await Task.detached {
                    AppUpdateGate.waitUntilCoreLive(socketURL: socketURL)
                }.value
                if !live {
                    try BundledCoreLauncher.launch(bundleURL: bundleURL)
                }
            } catch {
                Gmak8Log.ui.error(
                    "failed to restore gmak8-core: \(error.localizedDescription, privacy: .public)"
                )
            }
            presentUpdateFailure(error)
        }
    }

    private func presentUpdateFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "Update failed"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private final class Gmak8SparkleUserDriver: NSObject, SPUUserDriver {
    private let inner: SPUStandardUserDriver
    var interceptInstall: ((@escaping (SPUUserUpdateChoice) -> Void) -> Void)?

    init(hostBundle: Bundle) {
        inner = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        inner.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        inner.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        inner.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            guard choice == .install, state.stage == .installing, let intercept = self?.interceptInstall else {
                reply(choice)
                return
            }
            intercept(reply)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        inner.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        inner.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        inner.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        inner.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        inner.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        inner.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        inner.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        inner.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        inner.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        inner.showReady(toInstallAndRelaunch: { [weak self] choice in
            guard choice == .install, let intercept = self?.interceptInstall else {
                reply(choice)
                return
            }
            intercept(reply)
        })
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        inner.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        inner.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        inner.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        inner.showUpdateInFocus()
    }
}
