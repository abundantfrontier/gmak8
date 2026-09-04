import AppKit
import Combine
import Foundation
import Gmak8Kit
import Gmak8XPC
import Virtualization

enum SystemVirtualizationCapabilities {
    static var isSupported: Bool {
        VZVirtualMachine.isSupported
    }

    static var nestedVirtualizationSupported: Bool {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let platform: Bool
        if #available(macOS 15.0, *) {
            platform = VZGenericPlatformConfiguration.isNestedVirtualizationSupported
        } else {
            platform = false
        }
        return NestedVirtualizationProbe.isSupported(
            macOSMajor: major,
            platformReportsSupported: platform
        )
    }
}

enum AssetRowStatus: Equatable {
    case missing
    case ready
    case working
    case failed(String)
}

@MainActor
final class OnboardingSession: ObservableObject {
    @Published var page = OnboardingPage.welcome
    @Published var draft: OnboardingDraft
    @Published var lastError: String?
    @Published var cliPlan: CLIInstallPlan
    @Published var finishing = false

    let assets: ClusterAssetSession
    let host: HostSnapshot
    let permissions: PermissionsOutcome

    private let paths: HostPaths
    private let bundleURL: URL
    private let fileManager: FileManager
    private var assetsCancellable: AnyCancellable?

    init(
        paths: HostPaths = .current(),
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.bundleURL = bundleURL
        self.fileManager = fileManager
        self.assets = ClusterAssetSession(paths: paths, fileManager: fileManager)
        let host = SettingsStore.currentHostSnapshot()
        self.host = host
        self.draft = OnboardingDraft(host: host)
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
    }

    var visibleAssets: [OnboardingAssetKind] {
        assets.visibleAssets
    }

    var assetStatus: [OnboardingAssetKind: AssetRowStatus] {
        assets.assetStatus
    }

    var canAdvance: Bool {
        OnboardingAdvance.canLeave(
            page: page,
            permissions: permissions,
            guestReady: assetStatus[.guest] == .ready,
            airgapReady: assetStatus[.k3sAirgap] == .ready,
            profileAccepted: draft.profileIsAccepted,
            guestRequired: OnboardingAssets.isRequiredToContinue(.guest),
            airgapRequired: OnboardingAssets.isRequiredToContinue(.k3sAirgap)
        )
    }

    var showsInstallToApplications: Bool {
        permissions == .translocated
    }

    func installToApplications() {
        do {
            try ApplicationsBundleInstall.install(from: bundleURL, fileManager: fileManager)
            lastError = nil
            NSWorkspace.shared.open(ApplicationsBundleInstall.destination)
            NSApp.terminate(nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    var primaryTitle: String {
        page.primaryTitle
    }

    func back() {
        page = page.back()
        lastError = nil
    }

    func advance() {
        guard canAdvance else {
            return
        }
        page = page.advanced()
        lastError = nil
        if page == .assets {
            refreshCachedAssets()
        }
    }

    func applyProfile(_ profile: Profile) {
        draft.applyProfile(profile, host: host)
    }

    func refreshCachedAssets() {
        assets.refresh()
    }

    func download(_ kind: OnboardingAssetKind) {
        assets.download(kind)
        lastError = assets.lastError
    }

    func chooseFile(_ kind: OnboardingAssetKind) {
        assets.chooseFile(kind)
        lastError = assets.lastError
    }

    func finish(settingsStore: SettingsStore, clusterSession: ClusterSession) {
        guard canAdvance, page == .createCluster else {
            return
        }
        finishing = true
        lastError = nil
        do {
            let settings = try draft.makeSettings(host: host)
            do {
                try CLIPathInstaller.install(cliPlan, fileManager: fileManager)
            } catch {
                lastError = error.localizedDescription
                finishing = false
                return
            }
            settingsStore.completeOnboarding(settings)
            if settingsStore.needsOnboarding {
                finishing = false
                lastError = settingsStore.lastError ?? lastError
                return
            }
            try CoreLaunchAgent.register(bundleURL: bundleURL)
            clusterSession.startCluster(waitForEngine: true)
        } catch EngineErrorCode.translocated {
            settingsStore.lastError = OnboardingCopy.moveToApplications
            lastError = OnboardingCopy.moveToApplications
            finishing = false
        } catch {
            settingsStore.lastError = error.localizedDescription
            lastError = error.localizedDescription
            finishing = false
        }
    }

}
