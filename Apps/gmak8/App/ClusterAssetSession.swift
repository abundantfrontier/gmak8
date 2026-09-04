import AppKit
import Combine
import Foundation
import Gmak8Kit

@MainActor
final class ClusterAssetSession: ObservableObject {
    @Published var assetStatus: [OnboardingAssetKind: AssetRowStatus] = [
        .guest: .missing,
        .k3sAirgap: .missing,
        .kubevirtAirgap: .missing,
    ]
    @Published var lastError: String?
    @Published var guestItems: [AssetLibraryItem] = []
    @Published var k3sItems: [AssetLibraryItem] = []
    @Published var libraryRoot: URL

    let visibleAssets: [OnboardingAssetKind] = OnboardingAssets.visible(for: .kubernetes)

    private let paths: HostPaths
    private let publicKeyPEM: String
    private let fileManager: FileManager
    private let home: URL

    init(paths: HostPaths = .current(), fileManager: FileManager = .default, libraryFolderPath: String = "") {
        self.paths = paths
        self.fileManager = fileManager
        self.publicKeyPEM = (try? CosignPin.loadPublicKeyPEM()) ?? ""
        self.home = fileManager.homeDirectoryForCurrentUser
        self.libraryRoot = AssetLibrary.resolvedRoot(libraryFolderPath: libraryFolderPath, home: home)
    }

    func setLibraryFolderPath(_ path: String) {
        libraryRoot = AssetLibrary.resolvedRoot(libraryFolderPath: path, home: home)
        try? AssetLibrary.ensureLayout(at: libraryRoot, fileManager: fileManager)
        refresh()
    }

    func refresh() {
        try? AssetLibrary.ensureLayout(at: libraryRoot, fileManager: fileManager)
        if let cached = try? store(for: .k3sAirgap)?.cachedFileIfValid(fileManager: fileManager) {
            try? copyIntoLibrary(cached, kind: .k3sAirgap)
        }
        let scanned = AssetLibrary.scan(root: libraryRoot, fileManager: fileManager)
        guestItems = scanned.guest
        k3sItems = scanned.k3s
        for kind in visibleAssets {
            if assetStatus[kind] == .working {
                continue
            }
            switch kind {
            case .guest:
                adoptGuestFromLibrary()
            case .k3sAirgap, .kubevirtAirgap:
                adoptSignedAsset(kind)
            }
        }
    }

    func download(_ kind: OnboardingAssetKind) {
        guard let store = store(for: kind), store.pin.remoteDownloadEnabled else {
            return
        }
        assetStatus[kind] = .working
        lastError = nil
        Task {
            do {
                let cached = try await store.download()
                try copyIntoLibrary(cached, kind: kind)
                assetStatus[kind] = .ready
                refresh()
            } catch {
                let message = OnboardingCopy.userFacingAssetError(error)
                assetStatus[kind] = .failed(message)
                lastError = message
            }
        }
    }

    func useLibraryItem(_ item: AssetLibraryItem, kind: OnboardingAssetKind) {
        do {
            switch kind {
            case .guest:
                try GuestOSDiskInstall.install(from: item.url, to: paths.osImage, fileManager: fileManager)
            case .k3sAirgap, .kubevirtAirgap:
                guard let store = store(for: kind) else {
                    return
                }
                _ = try store.importLocalFile(item.url)
            }
            assetStatus[kind] = .ready
            lastError = nil
            refresh()
        } catch {
            let message = OnboardingCopy.userFacingAssetError(error)
            assetStatus[kind] = .failed(message)
            lastError = message
        }
    }

    func chooseFile(_ kind: OnboardingAssetKind) {
        guard OnboardingAssets.chooseFileEnabled(kind) else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message =
            kind == .guest ? OnboardingCopy.guestLocalFileHint : OnboardingCopy.useLocalFile
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            switch kind {
            case .guest:
                try copyPickedFile(url, into: AssetLibrary.guestDownloadDestination(root: libraryRoot, fileName: url.lastPathComponent))
                try GuestOSDiskInstall.install(from: url, to: paths.osImage, fileManager: fileManager)
            case .k3sAirgap, .kubevirtAirgap:
                guard let store = store(for: kind) else {
                    return
                }
                try copyPickedFile(url, into: AssetLibrary.k3sDownloadDestination(root: libraryRoot, fileName: url.lastPathComponent))
                _ = try store.importLocalFile(url)
            }
            assetStatus[kind] = .ready
            lastError = nil
            refresh()
        } catch {
            let message = OnboardingCopy.userFacingAssetError(error)
            assetStatus[kind] = .failed(message)
            lastError = message
        }
    }

    private func adoptGuestFromLibrary() {
        if GuestOSDiskInstall.containsBootSignature(at: paths.osImage) {
            assetStatus[.guest] = .ready
            return
        }
        guard let item = AssetLibrary.preferredGuestDisk(guestItems) else {
            assetStatus[.guest] = .missing
            return
        }
        do {
            try GuestOSDiskInstall.install(from: item.url, to: paths.osImage, fileManager: fileManager)
            assetStatus[.guest] = .ready
            lastError = nil
        } catch {
            let message = OnboardingCopy.userFacingAssetError(error)
            assetStatus[.guest] = .failed(message)
            lastError = message
        }
    }

    private func adoptSignedAsset(_ kind: OnboardingAssetKind) {
        do {
            if try store(for: kind)?.cachedFileIfValid(fileManager: fileManager) != nil {
                assetStatus[kind] = .ready
                return
            }
            guard kind == .k3sAirgap, let item = k3sItems.first, let store = store(for: kind) else {
                assetStatus[kind] = .missing
                return
            }
            _ = try store.importLocalFile(item.url)
            try copyIntoLibrary(store.archiveURL, kind: kind)
            assetStatus[kind] = .ready
            lastError = nil
        } catch {
            assetStatus[kind] = .failed(OnboardingCopy.userFacingAssetError(error))
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

    private func copyIntoLibrary(_ cached: URL, kind: OnboardingAssetKind) throws {
        let dest: URL
        switch kind {
        case .guest:
            dest = AssetLibrary.guestDownloadDestination(root: libraryRoot, fileName: cached.lastPathComponent)
        case .k3sAirgap, .kubevirtAirgap:
            dest = AssetLibrary.k3sDownloadDestination(root: libraryRoot, fileName: cached.lastPathComponent)
        }
        try copyPickedFile(cached, into: dest)
    }

    private func copyPickedFile(_ source: URL, into dest: URL) throws {
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: dest.path(percentEncoded: false)) {
            return
        }
        try fileManager.copyItem(at: source, to: dest)
    }
}
