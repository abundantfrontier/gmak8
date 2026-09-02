import AppKit
import Combine
import Gmak8Kit
import SwiftUI

enum Gmak8SceneID {
    static let main = ProductWindowIdentity.sceneID
    static let recovery = ProductWindowIdentity.recoverySceneID
}

@MainActor
final class Gmak8AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    static let hasAskedKeepRunningKey = "hasAskedKeepClusterRunningOnQuit"

    let session = ClusterSession()
    let settingsStore = SettingsStore()

    private var hasAskedFirstQuit: Bool
    private var forceStopAndQuit = false
    private var openWindow: ((String) -> Void)?
    private var settingsObservation: AnyCancellable?

    override init() {
        hasAskedFirstQuit = UserDefaults.standard.bool(forKey: Self.hasAskedKeepRunningKey)
        super.init()
        settingsObservation = settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !settingsStore.needsOnboarding {
            settingsStore.ensureCoreAgentRegistered()
            settingsStore.applyLaunchAtLoginIfNeeded()
        }
        session.startListening()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        if launchedAsLoginItem(), !settingsStore.needsOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.keepExtraHideWindows()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stopListening()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let intent: QuitIntent = forceStopAndQuit ? .stopAndQuit : .quitRequested
        forceStopAndQuit = false
        return applyTerminateAction(currentPolicy.action(for: intent))
    }

    func requestQuit() {
        forceStopAndQuit = false
        NSApp.terminate(nil)
    }

    func stopAndQuit() {
        forceStopAndQuit = true
        NSApp.terminate(nil)
    }

    func bindOpenWindow(_ openWindow: OpenWindowAction) {
        self.openWindow = { id in
            openWindow(id: id)
        }
    }

    func openMainWindow(_ openWindow: OpenWindowAction? = nil) {
        presentWindow(id: Gmak8SceneID.main, openWindow: openWindow)
        for window in NSApp.windows where isProductWindow(window) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openRecoveryWindow(_ openWindow: OpenWindowAction? = nil) {
        presentWindow(id: Gmak8SceneID.recovery, openWindow: openWindow)
    }

    func confirmAndResetCluster() {
        ResetAlert.present(sheetWindow: resetSheetWindow()) { [weak self] in
            self?.session.resetCluster()
        }
    }

    func openSettingsWindow() {
        guard FirstRunGate.clusterActionsEnabled(needsOnboarding: settingsStore.needsOnboarding) else {
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func presentWindow(id: String, openWindow: OpenWindowAction?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let openWindow {
            openWindow(id: id)
        } else {
            self.openWindow?(id)
        }
    }

    private var currentPolicy: QuitPolicy {
        QuitPolicy(
            keepClusterRunningOnQuit: settingsStore.keepClusterRunningOnQuit,
            hasAskedFirstQuit: hasAskedFirstQuit
        )
    }

    private func applyTerminateAction(_ action: QuitAction) -> NSApplication.TerminateReply {
        switch action {
        case .becomeAccessory(let stopCluster):
            becomeAccessory(stopCluster: stopCluster)
            return .terminateCancel
        case .showFirstQuitSheet(let defaultKeepRunning):
            DispatchQueue.main.async { [weak self] in
                self?.presentFirstQuitSheet(defaultKeepRunning: defaultKeepRunning)
            }
            return .terminateLater
        case .hideWindowsKeepExtra, .refuseHeadlessKeepExtra:
            keepExtraHideWindows()
            return .terminateCancel
        case .stopClusterThenTerminate:
            Task { [weak self] in
                await self?.session.stopClusterBestEffort()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }

    private func presentFirstQuitSheet(defaultKeepRunning: Bool) {
        let alert = NSAlert()
        alert.messageText = "Quit gmak8"
        alert.informativeText = FirstQuitPrompt.message
        if defaultKeepRunning {
            alert.addButton(withTitle: FirstQuitPrompt.keepRunningTitle)
            alert.addButton(withTitle: FirstQuitPrompt.stopAndQuitTitle)
        } else {
            alert.addButton(withTitle: FirstQuitPrompt.stopAndQuitTitle)
            alert.addButton(withTitle: FirstQuitPrompt.keepRunningTitle)
        }
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            let firstButton = response == .alertFirstButtonReturn
            let keep = FirstQuitPrompt.keepRunningChosen(
                firstButton: firstButton,
                defaultKeepRunning: defaultKeepRunning
            )
            self?.finishFirstQuit(keepRunning: keep)
        }
        if let window = NSApp.windows.first(where: { isProductWindow($0) && $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }

    private func finishFirstQuit(keepRunning: Bool) {
        let result = currentPolicy.applyingSheetChoice(keepRunning)
        hasAskedFirstQuit = result.policy.hasAskedFirstQuit
        UserDefaults.standard.set(true, forKey: Self.hasAskedKeepRunningKey)
        settingsStore.setKeepClusterRunningOnQuit(keepRunning)
        switch result.action {
        case .hideWindowsKeepExtra:
            keepExtraHideWindows()
            NSApp.reply(toApplicationShouldTerminate: false)
        case .stopClusterThenTerminate:
            Task { [weak self] in
                await self?.session.stopClusterBestEffort()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        default:
            keepExtraHideWindows()
            NSApp.reply(toApplicationShouldTerminate: false)
        }
    }

    private func applyCloseLastWindow() {
        switch currentPolicy.action(for: .closeLastWindow) {
        case .becomeAccessory(let stopCluster):
            becomeAccessory(stopCluster: stopCluster)
        default:
            becomeAccessory(stopCluster: false)
        }
    }

    private func becomeAccessory(stopCluster: Bool) {
        NSApp.setActivationPolicy(.accessory)
        if stopCluster {
            session.stopCluster()
        }
    }

    private func keepExtraHideWindows() {
        for window in NSApp.windows where shouldHideWhenKeepingExtra(window) {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        if isProductWindow(window) {
            DispatchQueue.main.async { [weak self] in
                self?.applyCloseLastWindow()
            }
            return
        }
        if isRecoveryWindow(window) {
            DispatchQueue.main.async { [weak self] in
                self?.applyRecoveryWindowClosed(excluding: window)
            }
        }
    }

    private func applyRecoveryWindowClosed(excluding window: NSWindow) {
        let productVisible = NSApp.windows.contains {
            $0 !== window && $0.isVisible && isProductWindow($0)
        }
        let recoveryVisible = NSApp.windows.contains {
            $0 !== window && $0.isVisible && isRecoveryWindow($0)
        }
        if !productVisible && !recoveryVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func resetSheetWindow() -> NSWindow? {
        if let recovery = NSApp.windows.first(where: { $0.isVisible && isRecoveryWindow($0) && !($0 is NSPanel) }) {
            return recovery
        }
        return NSApp.windows.first { window in
            window.isVisible
                && ProductWindowIdentity.isResetSheetHost(
                    identifier: window.identifier?.rawValue,
                    title: window.title,
                    isStatusBar: window.level == .statusBar,
                    isPanel: window is NSPanel
                )
        }
    }

    private func isProductWindow(_ window: NSWindow) -> Bool {
        ProductWindowIdentity.isProductWindow(
            identifier: window.identifier?.rawValue,
            title: window.title,
            isStatusBar: window.level == .statusBar
        )
    }

    private func isRecoveryWindow(_ window: NSWindow) -> Bool {
        ProductWindowIdentity.isRecoveryWindow(
            identifier: window.identifier?.rawValue,
            title: window.title,
            isStatusBar: window.level == .statusBar
        )
    }

    private func shouldHideWhenKeepingExtra(_ window: NSWindow) -> Bool {
        ProductWindowIdentity.shouldHideWhenKeepingExtra(isStatusBar: window.level == .statusBar)
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        let launchedAsLoginItem: OSType = 0x6C67_6974
        let propData: AEKeyword = 0x7072_6474
        return event.eventID == OSType(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: propData)?.enumCodeValue == launchedAsLoginItem
    }
}
