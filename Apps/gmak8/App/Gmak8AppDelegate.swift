import AppKit
import Combine
import SwiftUI

enum Gmak8SceneID {
    static let main = "main"
}

@MainActor
final class Gmak8AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    static let hasAskedKeepRunningKey = "hasAskedKeepClusterRunningOnQuit"

    let session = ClusterSession()
    let settingsStore = SettingsStore()

    private var hasAskedFirstQuit: Bool
    private var forceStopAndQuit = false
    private var openWindow: (() -> Void)?

    override init() {
        hasAskedFirstQuit = UserDefaults.standard.bool(forKey: Self.hasAskedKeepRunningKey)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.startListening()
        settingsStore.applyLaunchAtLoginIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        if launchedAsLoginItem() {
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
        self.openWindow = { openWindow(id: Gmak8SceneID.main) }
    }

    func openMainWindow(_ openWindow: OpenWindowAction? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let openWindow {
            openWindow(id: Gmak8SceneID.main)
        } else {
            self.openWindow?()
        }
        for window in NSApp.windows where isMainWindow(window) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            presentFirstQuitSheet(defaultKeepRunning: defaultKeepRunning)
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
        if let window = NSApp.windows.first(where: { isMainWindow($0) && $0.isVisible }) {
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
        for window in NSApp.windows where isMainWindow(window) {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let visibleMains = NSApp.windows.filter { self.isMainWindow($0) && $0.isVisible }
            if visibleMains.isEmpty {
                self.applyCloseLastWindow()
            }
        }
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else {
            return false
        }
        if window.level == .statusBar {
            return false
        }
        let name = String(describing: type(of: window))
        if name.contains("StatusBar") || name.contains("NSStatusBar") {
            return false
        }
        return true
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
