import AppKit
import Combine
import Foundation
import Gmak8Kit
import Gmak8XPC

enum SetupSection: String, CaseIterable, Identifiable, Hashable {
    case getStarted
    case folder
    case guest
    case k3s
    case mac
    case cluster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .getStarted: OnboardingCopy.getStartedSection
        case .folder: OnboardingCopy.folderSection
        case .guest: OnboardingCopy.guestSection
        case .k3s: OnboardingCopy.k3sSection
        case .mac: OnboardingCopy.macSection
        case .cluster: OnboardingCopy.clusterSection
        }
    }
}

@MainActor
final class SetupSession: ObservableObject {
    @Published var section: SetupSection? = .getStarted

    let assets: ClusterAssetSession
    let permissions: PermissionsOutcome
    let host: HostSnapshot
    let cliPlan: CLIInstallPlan
    let bundleURL: URL

    private var assetsCancellable: AnyCancellable?

    init(
        libraryFolderPath: String,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        self.bundleURL = bundleURL
        self.assets = ClusterAssetSession(fileManager: fileManager, libraryFolderPath: libraryFolderPath)
        self.host = SettingsStore.currentHostSnapshot()
        self.permissions = PermissionsProbe.evaluate(
            virtualizationSupported: SystemVirtualizationCapabilities.isSupported,
            nestedVirtualizationSupported: SystemVirtualizationCapabilities.nestedVirtualizationSupported,
            shouldRefuseLaunchAgent: TranslocationChecker().shouldRefuseRegister(bundleURL: bundleURL)
        )
        self.cliPlan = CLIPathInstaller.plan(
            home: fileManager.homeDirectoryForCurrentUser,
            pathEnvironment: ProcessInfo.processInfo.environment["PATH"] ?? "",
            bundleURL: bundleURL,
            fileManager: fileManager
        )
        assetsCancellable = assets.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        assets.refresh()
    }

    var showsInstallToApplications: Bool {
        permissions == .translocated
    }

    func installToApplications() {
        do {
            try ApplicationsBundleInstall.install(from: bundleURL)
            NSWorkspace.shared.open(ApplicationsBundleInstall.destination)
            NSApp.terminate(nil)
        } catch {
            assets.lastError = error.localizedDescription
        }
    }

    func chooseLibraryFolder(settingsStore: SettingsStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = OnboardingCopy.chooseFolder
        panel.directoryURL = assets.libraryRoot
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        settingsStore.setLibraryFolder(url)
        assets.setLibraryFolderPath(url.path(percentEncoded: false))
    }

    func revealLibrary() {
        try? AssetLibrary.ensureLayout(at: assets.libraryRoot)
        NSWorkspace.shared.open(assets.libraryRoot)
    }

    func revealGuestFolder() {
        try? AssetLibrary.ensureLayout(at: assets.libraryRoot)
        NSWorkspace.shared.open(
            assets.libraryRoot.appending(path: AssetLibrary.guestSubdirectory, directoryHint: .isDirectory)
        )
    }

    func openMkosiTerminal(settingsStore: SettingsStore) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let found = MkosiWorkingDirectory.resolve(
            home: home,
            savedRepoPath: settingsStore.settings.sourceRepoPath
        ) {
            TerminalLauncher.open(workingDirectory: found)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = OnboardingCopy.chooseMkosiRepo
        panel.directoryURL = home.appending(path: "Documents/GitHub/gmak8", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard let mkosi = MkosiWorkingDirectory.resolved(fromPicked: url) else {
            assets.lastError = OnboardingCopy.mkosiRepoMissing
            return
        }
        settingsStore.update { settings in
            settings.sourceRepoPath = mkosi.path(percentEncoded: false)
        }
        assets.lastError = nil
        TerminalLauncher.open(workingDirectory: mkosi)
    }

    func applyProfile(_ profile: Profile, settingsStore: SettingsStore) {
        settingsStore.applyProfile(profile)
        assets.profile = settingsStore.settings.profile
    }

    func start(settingsStore: SettingsStore, clusterSession: ClusterSession) {
        assets.refresh()
        do {
            try CLIPathInstaller.install(cliPlan)
        } catch {
            assets.lastError = error.localizedDescription
        }
        settingsStore.ensureCoreAgentRegistered()
        clusterSession.startCluster(waitForEngine: true)
    }
}
