import AppKit
import Gmak8Kit
import Gmak8XPC
import SwiftUI

struct SetupSplitView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @StateObject private var setup: SetupSession

    init() {
        _setup = StateObject(
            wrappedValue: SetupSession(libraryFolderPath: "")
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SetupSection.allCases, selection: $setup.section) { section in
                    Text(section.title).tag(section)
                }
                .navigationSplitViewColumnWidth(min: 140, ideal: 168, max: 220)
                VStack(alignment: .leading, spacing: 8) {
                    Text(StatusText.displayName(session.status.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if session.canStart {
                        Button(OnboardingCopy.createAndStart) {
                            setup.start(settingsStore: settingsStore, clusterSession: session)
                        }
                        .disabled(!clusterReadyToStart)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Stop") {
                            session.stopCluster()
                        }
                        .disabled(!session.canStop)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(OnboardingCopy.setupTitle)
        } detail: {
            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
            }
        }
        .onAppear {
            reloadAssets()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadAssets()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch setup.section ?? .getStarted {
        case .getStarted:
            getStartedPane
        case .folder:
            folderPane
        case .guest:
            guestPane
        case .k3s:
            k3sPane
        case .mac:
            macPane
        case .cluster:
            clusterPane
        }
    }

    private var getStartedPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(OnboardingCopy.getStartedSection)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.getStartedBody)
                .foregroundStyle(.secondary)
            if setup.assets.assetStatus[.k3sAirgap] == .ready {
                Text(OnboardingCopy.k3sImagesReady)
            } else {
                Text(OnboardingCopy.stepK3s)
                    .foregroundStyle(.secondary)
                Button(OnboardingCopy.downloadThisPack) {
                    setup.assets.download(.k3sAirgap)
                }
                .disabled(setup.assets.assetStatus[.k3sAirgap] == .working)
            }
            if setup.assets.assetStatus[.guest] == .ready {
                Text(OnboardingCopy.stepGuestReady)
            } else {
                Text(OnboardingCopy.stepGuestWaiting)
                    .foregroundStyle(.secondary)
                Text(OnboardingCopy.guestHowToBuild)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
                HStack {
                    Button(OnboardingCopy.revealInFinder) {
                        setup.revealGuestFolder()
                    }
                    Button(OnboardingCopy.openTerminal) {
                        setup.openMkosiTerminal(settingsStore: settingsStore)
                    }
                }
            }
            if session.status.state == .starting {
                Text(OnboardingCopy.linuxBooting)
                    .foregroundStyle(.secondary)
            }
            if let error = friendlyStartError {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if clusterReadyToStart, session.canStart {
                Button(OnboardingCopy.createAndStart) {
                    setup.start(settingsStore: settingsStore, clusterSession: session)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var folderPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.folderSection)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.folderBody)
                .foregroundStyle(.secondary)
            Text(setup.assets.libraryRoot.path(percentEncoded: false))
                .font(.caption)
                .textSelection(.enabled)
            HStack {
                Button(OnboardingCopy.chooseFolder) {
                    setup.chooseLibraryFolder(settingsStore: settingsStore)
                }
                Button(OnboardingCopy.revealInFinder) {
                    setup.revealLibrary()
                }
            }
        }
    }

    private var guestPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.guestSection)
                .font(.title2)
                .fontWeight(.semibold)
            if setup.assets.assetStatus[.guest] == .ready {
                Text(OnboardingCopy.stepGuestReady)
            } else if OnboardingAssets.remoteDownloadEnabled(.guest) {
                Text(OnboardingCopy.stepGuestWaiting)
                    .foregroundStyle(.secondary)
                Button(OnboardingCopy.download) {
                    setup.assets.download(.guest)
                }
                .disabled(setup.assets.assetStatus[.guest] == .working)
            } else {
                Text(OnboardingCopy.stepGuestWaiting)
                    .foregroundStyle(.secondary)
                Text(OnboardingCopy.guestHowToBuild)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
                HStack {
                    Button(OnboardingCopy.revealInFinder) {
                        setup.revealGuestFolder()
                    }
                    Button(OnboardingCopy.openTerminal) {
                        setup.openMkosiTerminal(settingsStore: settingsStore)
                    }
                }
            }
            if !setup.assets.guestItems.isEmpty {
                ForEach(setup.assets.guestItems) { item in
                    libraryRow(item, kind: .guest)
                }
            }
            if let error = setup.assets.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var k3sPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.k3sSection)
                .font(.title2)
                .fontWeight(.semibold)
            if setup.assets.assetStatus[.k3sAirgap] == .ready {
                Text(OnboardingCopy.k3sImagesReady)
            } else {
                Text(OnboardingCopy.k3sImagesNeeded)
                    .foregroundStyle(.secondary)
                Button(OnboardingCopy.downloadThisPack) {
                    setup.assets.download(.k3sAirgap)
                }
                .disabled(setup.assets.assetStatus[.k3sAirgap] == .working)
                if let error = setup.assets.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var macPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.macSection)
                .font(.title2)
                .fontWeight(.semibold)
            Text(PermissionsProbe.message(setup.permissions))
                .foregroundStyle(setup.permissions.canContinue ? Color.secondary : Color.red)
            if setup.showsInstallToApplications {
                Button(OnboardingCopy.installToApplications) {
                    setup.installToApplications()
                }
            }
            Text(CoreLaunchAgent.twoLoginItemsExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(OnboardingCopy.noFullDiskAccess)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(StatusPresentation.nestedVirtLine(session.status.nestedVirt))
                .font(.caption)
        }
    }

    private var clusterPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.clusterSection)
                .font(.title2)
                .fontWeight(.semibold)
            Text(StatusText.displayName(session.status.state))
                .foregroundStyle(.secondary)
            if let message = friendlyStartError {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Picker("Profile", selection: profileBinding) {
                ForEach(Profile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(.radioGroup)
            Text(
                "This Mac: \(setup.host.processorCount) CPU, \(setup.host.physicalMemoryGiB) GiB RAM, \(setup.host.freeDiskGiB) GiB free disk."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Stepper(value: cpuBinding, in: 1...max(1, setup.host.processorCount)) {
                Text("vCPU \(settingsStore.settings.cpu)")
            }
            Stepper(value: memoryBinding, in: 2...max(2, setup.host.physicalMemoryGiB)) {
                Text("RAM \(settingsStore.settings.memoryGiB) GiB")
            }
            Stepper(value: diskBinding, in: 20...1_024) {
                Text("Disk \(settingsStore.settings.dataDiskGiB) GiB")
            }
            Text(OnboardingCopy.sparseDisk)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(OnboardingCopy.clusterName)
                TextField(OnboardingCopy.clusterName, text: clusterNameBinding)
            }
            HStack {
                Text(OnboardingCopy.kubernetesVersion)
                Text(OnboardingCopy.kubernetesVersionValue)
                    .foregroundStyle(.secondary)
            }
            Toggle(OnboardingCopy.currentContextCheckbox, isOn: currentContextBinding)
            Text(OnboardingCopy.timeMachine)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if session.canStart {
                    Button(OnboardingCopy.createAndStart) {
                        setup.start(settingsStore: settingsStore, clusterSession: session)
                    }
                    .disabled(!clusterReadyToStart)
                } else {
                    Button("Stop") {
                        session.stopCluster()
                    }
                    .disabled(!session.canStop)
                }
                Button("Diagnostics") {
                    appDelegate.openRecoveryWindow()
                }
                Button("Reset…") {
                    appDelegate.confirmAndResetCluster()
                }
            }
        }
    }

    private var guestRuntimeLine: some View {
        let ready = setup.assets.assetStatus[.guest] == .ready
        return Text(ready ? OnboardingCopy.stepGuestReady : OnboardingCopy.guestRuntimeWaiting)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var k3sRuntimeLine: some View {
        let status = setup.assets.assetStatus[.k3sAirgap] ?? .missing
        let text: String
        switch status {
        case .ready: text = OnboardingCopy.k3sImagesReady
        case .working: text = "Downloading…"
        case .failed(let message): text = message
        case .missing: text = OnboardingCopy.k3sImagesNeeded
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(statusColor(status))
    }

    private func libraryRow(_ item: AssetLibraryItem, kind: OnboardingAssetKind) -> some View {
        HStack {
            Text(item.relativePath)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
            Button(OnboardingCopy.useThis) {
                setup.assets.useLibraryItem(item, kind: kind)
            }
        }
    }

    private func reloadAssets() {
        setup.assets.setLibraryFolderPath(settingsStore.settings.libraryFolderPath)
    }

    private var clusterReadyToStart: Bool {
        setup.assets.assetStatus[.guest] == .ready && setup.assets.assetStatus[.k3sAirgap] == .ready
    }

    private var friendlyStartError: String? {
        let raw = session.status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.contains("linux disk") || lower.contains("guest os") || lower.contains("os.img")
            || lower.contains("mkosi")
        {
            return OnboardingCopy.stepGuestWaiting
        }
        return raw
    }

    private func statusColor(_ status: AssetRowStatus) -> Color {
        switch status {
        case .failed: .red
        default: .secondary
        }
    }

    private var profileBinding: Binding<Profile> {
        Binding(
            get: { settingsStore.settings.profile },
            set: { setup.applyProfile($0, settingsStore: settingsStore) }
        )
    }

    private var clusterNameBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.clusterName },
            set: { name in
                settingsStore.update { $0.clusterName = name }
            }
        )
    }

    private var currentContextBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.setCurrentContextOnStart },
            set: { value in
                settingsStore.update { $0.setCurrentContextOnStart = value }
            }
        )
    }

    private var cpuBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.cpu },
            set: { value in
                settingsStore.update { $0.cpu = value }
            }
        )
    }

    private var memoryBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.memoryGiB },
            set: { value in
                settingsStore.update { $0.memoryGiB = value }
            }
        )
    }

    private var diskBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.dataDiskGiB },
            set: { value in
                settingsStore.update { $0.dataDiskGiB = value }
            }
        )
    }
}
