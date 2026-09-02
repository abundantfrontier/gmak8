import Gmak8Kit
import Gmak8XPC
import SwiftUI

@main
struct Gmak8App: App {
    @NSApplicationDelegateAdaptor(Gmak8AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(ProductWindowIdentity.title, id: Gmak8SceneID.main) {
            RootView()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.session)
                .environmentObject(appDelegate.settingsStore)
        }
        .defaultSize(width: 640, height: 520)

        Window(ProductWindowIdentity.recoveryTitle, id: Gmak8SceneID.recovery) {
            RecoveryView()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.session)
                .environmentObject(appDelegate.settingsStore)
        }
        .defaultSize(width: 520, height: 420)

        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.session)
                .environmentObject(appDelegate.settingsStore)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.session)
        }
        .menuBarExtraStyle(.window)
        .commands {
            Gmak8Commands(appDelegate: appDelegate, settingsStore: appDelegate.settingsStore)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.settingsStore)
        }
    }
}

struct Gmak8Commands: Commands {
    var appDelegate: Gmak8AppDelegate
    @ObservedObject var settingsStore: SettingsStore

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit gmak8…") {
                appDelegate.requestQuit()
            }
            .keyboardShortcut("q")
            Button("Stop Cluster and Quit") {
                appDelegate.stopAndQuit()
            }
            .keyboardShortcut("q", modifiers: [.command, .option])
            .disabled(!clusterActionsEnabled)
        }
        CommandGroup(after: .appInfo) {
            Button(AppUpdateCopy.checkForUpdates) {
                appDelegate.checkForUpdates()
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appDelegate.openSettingsWindow()
            }
            .keyboardShortcut(",")
            .disabled(!clusterActionsEnabled)
        }
        CommandGroup(after: .windowList) {
            Button("Open gmak8") {
                appDelegate.openMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("Open Terminal") {
                TerminalLauncher.open()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!clusterActionsEnabled)
            Button("Recovery / Diagnostics") {
                appDelegate.openRecoveryWindow()
            }
        }
    }

    private var clusterActionsEnabled: Bool {
        FirstRunGate.clusterActionsEnabled(needsOnboarding: settingsStore.needsOnboarding)
    }
}
