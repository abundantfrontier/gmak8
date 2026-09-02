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
    @Published var assetStatus: [OnboardingAssetKind: AssetRowStatus] = [
        .guest: .missing,
        .k3sAirgap: .missing,
        .kubevirtAirgap: .missing,
    ]
    @Published var lastError: String?
    @Published var cliPlan: CLIInstallPlan
    @Published var finishing = false

    let host: HostSnapshot
    let permissions: PermissionsOutcome

    private let paths: HostPaths
    private let publicKeyPEM: String
    private let bundleURL: URL
    private let fileManager: FileManager

    init(
        paths: HostPaths = .current(),
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.bundleURL = bundleURL
        self.fileManager = fileManager
        self.publicKeyPEM = (try? CosignPin.loadPublicKeyPEM()) ?? ""
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
    }

    var visibleAssets: [OnboardingAssetKind] {
        OnboardingAssets.visible(for: draft.profile)
    }

    var canAdvance: Bool {
        OnboardingAdvance.canLeave(
            page: page,
            permissions: permissions,
            guestReady: assetStatus[.guest] == .ready,
            airgapReady: assetStatus[.k3sAirgap] == .ready,
            profileAccepted: draft.profileIsAccepted
        )
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
        for kind in OnboardingAssetKind.allCases {
            if assetStatus[kind] == .working {
                continue
            }
            do {
                if try store(for: kind)?.cachedFileIfValid() != nil {
                    assetStatus[kind] = .ready
                } else if assetStatus[kind] != .ready {
                    assetStatus[kind] = .missing
                }
            } catch {
                assetStatus[kind] = .failed(OnboardingCopy.userFacingAssetError(error))
            }
        }
    }

    func download(_ kind: OnboardingAssetKind) {
        guard let store = store(for: kind) else {
            return
        }
        assetStatus[kind] = .working
        lastError = nil
        Task {
            do {
                _ = try await store.download()
                assetStatus[kind] = .ready
            } catch {
                let message = OnboardingCopy.userFacingAssetError(error)
                assetStatus[kind] = .failed(message)
                lastError = message
            }
        }
    }

    func chooseFile(_ kind: OnboardingAssetKind) {
        guard let store = store(for: kind) else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = OnboardingCopy.chooseFile
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            _ = try store.importLocalFile(url)
            assetStatus[kind] = .ready
            lastError = nil
        } catch {
            let message = OnboardingCopy.userFacingAssetError(error)
            assetStatus[kind] = .failed(message)
            lastError = message
        }
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
            }
            settingsStore.completeOnboarding(settings)
            if settingsStore.needsOnboarding {
                finishing = false
                lastError = settingsStore.lastError ?? lastError
                return
            }
            try CoreLaunchAgent.register(bundleURL: bundleURL)
            clusterSession.startCluster()
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

    private func store(for kind: OnboardingAssetKind) -> SignedAssetStore? {
        switch kind {
        case .guest:
            return SignedAssetStore(
                cacheDirectory: paths.guestCacheDirectory,
                pin: GuestAssetPin.bundled.signed,
                publicKeyPEM: publicKeyPEM,
                label: kind.title
            )
        case .k3sAirgap:
            return SignedAssetStore(
                cacheDirectory: paths.airgapCacheDirectory,
                pin: AirgapPin.bundled.signed,
                publicKeyPEM: publicKeyPEM,
                label: kind.title
            )
        case .kubevirtAirgap:
            return nil
        }
    }
}
