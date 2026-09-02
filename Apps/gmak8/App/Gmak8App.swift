import SwiftUI

@main
struct Gmak8App: App {
    @NSApplicationDelegateAdaptor(Gmak8AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(ProductWindowIdentity.title, id: Gmak8SceneID.main) {
            ContentView()
                .environmentObject(appDelegate)
                .environmentObject(appDelegate.session)
                .environmentObject(appDelegate.settingsStore)
        }
        .defaultSize(width: 420, height: 280)

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
            Gmak8Commands(appDelegate: appDelegate)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.settingsStore)
        }
    }
}

struct Gmak8Commands: Commands {
    var appDelegate: Gmak8AppDelegate

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
        }
    }
}
