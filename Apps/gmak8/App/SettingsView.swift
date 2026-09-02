import Gmak8Kit
import Gmak8XPC
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { settingsStore.settings.launchAtLogin },
                        set: { settingsStore.setLaunchAtLogin($0) }
                    )
                )
                Toggle(
                    "Keep cluster running when window closes",
                    isOn: Binding(
                        get: { settingsStore.settings.keepClusterRunningOnQuit },
                        set: { settingsStore.setKeepClusterRunningOnQuit($0) }
                    )
                )
                Text(CoreLaunchAgent.twoLoginItemsExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("General")
            }
            Section {
                Button(AppUpdateCopy.checkForUpdates) {
                    appDelegate.checkForUpdates()
                }
                Text(AppUpdateCopy.restartsCluster)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Updates")
            }
            if let error = settingsStore.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 240)
        .padding()
        .disabled(!FirstRunGate.clusterActionsEnabled(needsOnboarding: settingsStore.needsOnboarding))
    }
}
