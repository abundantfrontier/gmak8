import AppKit
import Gmak8Kit
import Gmak8XPC
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @State private var registryHost = ""
    @State private var registryUser = ""
    @State private var registryPassword = ""

    var body: some View {
        TabView {
            general.tabItem { Text(SettingsCopy.general) }
            resources.tabItem { Text(SettingsCopy.resources) }
            kubernetes.tabItem { Text(SettingsCopy.kubernetes) }
            files.tabItem { Text(SettingsCopy.files) }
            network.tabItem { Text(SettingsCopy.network) }
            advanced.tabItem { Text(SettingsCopy.advanced) }
            privacy.tabItem { Text(SettingsCopy.privacy) }
        }
        .frame(minWidth: 520, minHeight: 420)
        .padding()
        .disabled(!FirstRunGate.clusterActionsEnabled(needsOnboarding: settingsStore.needsOnboarding))
    }

    private var settings: ClusterSettings { settingsStore.settings }

    private var general: some View {
        Form {
            Section {
                Toggle(
                    SettingsCopy.launchAtLogin,
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settingsStore.setLaunchAtLogin($0) }
                    )
                )
                Toggle(
                    SettingsCopy.keepRunning,
                    isOn: Binding(
                        get: { settings.keepClusterRunningOnQuit },
                        set: { settingsStore.setKeepClusterRunningOnQuit($0) }
                    )
                )
                Toggle(
                    SettingsCopy.setCurrentContext,
                    isOn: boolBinding(\.setCurrentContextOnStart)
                )
                Toggle(
                    SettingsCopy.startClusterAtLogin,
                    isOn: boolBinding(\.startClusterAtLogin)
                )
                Text(CoreLaunchAgent.twoLoginItemsExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button(AppUpdateCopy.checkForUpdates) {
                    appDelegate.checkForUpdates()
                }
                Text(AppUpdateCopy.restartsCluster)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(SettingsCopy.updates)
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var resources: some View {
        Form {
            Section {
                LabeledContent("CPU") {
                    Stepper(value: intBinding(\.cpu), in: 1...max(1, ProcessInfo.processInfo.processorCount)) {
                        Text("\(settings.cpu)")
                    }
                }
                LabeledContent("Memory") {
                    Stepper(value: intBinding(\.memoryGiB), in: 2...64) {
                        Text("\(settings.memoryGiB) GiB")
                    }
                }
                Text(SettingsCopy.appliesNextStart)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Data disk") {
                    Text("\(settings.dataDiskGiB) GiB")
                }
                Text(SettingsCopy.diskCapLocked)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(SettingsCopy.balloon, isOn: .constant(false))
                    .disabled(true)
                Text(SettingsCopy.balloonUnsupported)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var kubernetes: some View {
        Form {
            Section {
                Picker("Profile", selection: profileBinding) {
                    ForEach(Profile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                if settings.profile == .eureka || settings.profile == .eurekaAPIOnly {
                    Text(OnboardingCopy.eurekaExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let refusal = settingsStore.profileRefusal {
                    Text(refusal.onboardingMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Button(OnboardingCopy.useEurekaAPIOnly) {
                        settingsStore.applyProfile(.eurekaAPIOnly)
                    }
                }
                TextField(SettingsCopy.clusterName, text: stringBinding(\.clusterName))
                Text(SettingsCopy.clusterNameReset)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(SettingsCopy.k3sVersion) {
                    Text(K3sPin.displayVersion)
                }
                Toggle(
                    SettingsCopy.kubeVirtAddon,
                    isOn: Binding(
                        get: { settings.kubeVirtEnabled },
                        set: { value in
                            settingsStore.update { $0.kubeVirtAddon = value }
                        }
                    )
                )
                .disabled(settings.profile != .kubernetes)
                Text(SettingsCopy.kubeVirtForced)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("traefik", isOn: boolBinding(\.disableTraefik))
                Toggle("servicelb", isOn: boolBinding(\.disableServiceLB))
                Toggle("local-storage", isOn: boolBinding(\.disableLocalStorage))
                Toggle("metrics-server", isOn: boolBinding(\.disableMetricsServer))
                Text(SettingsCopy.coreDNSRequired)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(SettingsCopy.disableBundled)
            }
            Section {
                LabeledContent(SettingsCopy.storageClass) {
                    Text(SettingsCopy.storageClassValue)
                }
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var files: some View {
        Form {
            Section {
                LabeledContent(SettingsCopy.hostUID) {
                    Text(HostUserIdentity.display)
                        .textSelection(.enabled)
                }
                Text(HostUserIdentity.warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SettingsCopy.noHomeShare)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(settings.hostMounts) { mount in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(mount.name)
                            Text(mount.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(mount.guestPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if mount.readOnly {
                            Text("read-only")
                                .font(.caption)
                        }
                        Button("Remove") {
                            settingsStore.update { current in
                                current.hostMounts.removeAll { $0.id == mount.id }
                            }
                        }
                    }
                }
                Button(SettingsCopy.addFolder) {
                    addHostFolder()
                }
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var network: some View {
        Form {
            Section {
                LabeledContent(SettingsCopy.apiBind) {
                    Text(SettingsCopy.apiBindValue)
                }
                LabeledContent(SettingsCopy.apiPort) {
                    Text("\(settings.apiPort)")
                }
                LabeledContent(SettingsCopy.ingress) {
                    Text(SettingsCopy.ingressValue)
                }
                Toggle(SettingsCopy.publishNodePorts, isOn: boolBinding(\.publishNodePorts))
                Toggle(SettingsCopy.publishL1SSH, isOn: boolBinding(\.publishL1SSH))
                    .disabled(settings.profile != .eureka)
                Text(SettingsCopy.virtctlHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SettingsCopy.publishL1SSHHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SettingsCopy.proxyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextEditor(text: stringBinding(\.registriesYAML))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                Text(SettingsCopy.registriesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(SettingsCopy.registries)
            }
            Section {
                TextField(SettingsCopy.registryHost, text: $registryHost)
                TextField(SettingsCopy.registryUser, text: $registryUser)
                SecureField(SettingsCopy.registryPassword, text: $registryPassword)
                Button(SettingsCopy.saveRegistry) {
                    saveRegistry()
                }
                .disabled(registryHost.isEmpty || registryUser.isEmpty || registryPassword.isEmpty)
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Section {
                Toggle(SettingsCopy.guestSSH, isOn: boolBinding(\.guestSSHDebug))
                Button(SettingsCopy.resetFactory) {
                    appDelegate.confirmAndResetCluster()
                }
            }
            errorSection
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section {
                Toggle(SettingsCopy.telemetry, isOn: .constant(false))
                    .disabled(true)
                Text(SettingsCopy.telemetryOff)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = settingsStore.lastError {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private var profileBinding: Binding<Profile> {
        Binding(
            get: { settings.profile },
            set: { settingsStore.applyProfile($0) }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ClusterSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<ClusterSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<ClusterSettings, String>) -> Binding<String> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { value in
                settingsStore.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func addHostFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to share with the guest at /mnt/host/<name>."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let suggested = HostMountName.sanitize(url.lastPathComponent) ?? HostMountName.sanitize("share")
        guard let name = suggested else {
            return
        }
        let mount = HostMount(name: name, path: url.path(percentEncoded: false))
        settingsStore.update { current in
            current.hostMounts.removeAll { $0.name == name }
            current.hostMounts.append(mount)
        }
    }

    private func saveRegistry() {
        let host = registryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = registryUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !user.isEmpty, !registryPassword.isEmpty else {
            return
        }
        do {
            try RegistryKeychain.setPassword(registryPassword, host: host)
            settingsStore.update { current in
                current.registryHosts.removeAll { $0.host == host }
                current.registryHosts.append(RegistryHost(host: host, username: user))
            }
            registryPassword = ""
        } catch {
            settingsStore.lastError = error.localizedDescription
        }
    }
}
