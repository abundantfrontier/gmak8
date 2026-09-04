import Combine
import Foundation
import Gmak8Kit
import Gmak8XPC

@MainActor
final class SettingsStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var settings: Settings
    @Published private(set) var needsOnboarding: Bool
    @Published var lastError: String?

    private let paths: HostPaths
    private let fileManager: FileManager

    init(paths: HostPaths = .current(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        let settingsExist = fileManager.fileExists(atPath: paths.settingsFile.path(percentEncoded: false))
        self.needsOnboarding = FirstRunGate.shouldShowOnboarding(settingsFileExists: settingsExist)
        self.settings = SettingsStore.loadOrDefault(paths: paths, fileManager: fileManager)
        if !settingsExist {
            try? self.settings.save(to: paths.settingsFile, fileManager: fileManager)
            try? AssetLibrary.ensureLayout(
                at: self.settings.libraryRoot(home: fileManager.homeDirectoryForCurrentUser),
                fileManager: fileManager
            )
            try? TimeMachineExclusion.excludeVMDirectory(at: paths.vmDirectory, fileManager: fileManager)
        }
    }

    func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        persist()
    }

    func setLibraryFolder(_ url: URL) {
        settings.libraryFolderPath = url.path(percentEncoded: false)
        persist()
        try? AssetLibrary.ensureLayout(at: url, fileManager: fileManager)
    }

    var keepClusterRunningOnQuit: Bool {
        settings.keepClusterRunningOnQuit
    }

    func setKeepClusterRunningOnQuit(_ value: Bool) {
        settings.keepClusterRunningOnQuit = value
        persistIfOnboardingComplete()
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard FirstRunGate.clusterActionsEnabled(needsOnboarding: needsOnboarding) else {
            return
        }
        do {
            try applyLaunchAtLogin(value)
            settings.launchAtLogin = value
            persistIfOnboardingComplete()
            lastError = nil
        } catch EngineErrorCode.translocated {
            lastError = RecoveryCopy.translocated
        } catch {
            lastError = RecoveryCopy.loginItemDenied
        }
    }

    func completeOnboarding(_ newSettings: Settings) {
        settings = newSettings
        persist()
        if lastError == nil {
            needsOnboarding = false
            try? TimeMachineExclusion.excludeVMDirectory(at: paths.vmDirectory, fileManager: fileManager)
        }
    }

    func applyLaunchAtLoginIfNeeded() {
        guard settings.launchAtLogin else {
            return
        }
        apply(LaunchAtLoginPolicy.mutation(enabling: true))
    }

    func ensureCoreAgentRegistered() {
        let socketURL = paths.engineSocket
        do {
            try CoreLaunchAgent.ensureRunning(
                bundleURL: Bundle.main.bundleURL,
                socketIsLive: EngineSocketProbe.isLive(socketURL),
                isLive: { EngineSocketProbe.isLive(socketURL) },
                launch: BundledCoreLauncher.launch
            )
            lastError = nil
        } catch EngineErrorCode.translocated {
            lastError = RecoveryCopy.translocated
        } catch {
            lastError = RecoveryCopy.loginItemDenied
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) throws {
        try LaunchAtLoginPolicy.apply(
            LaunchAtLoginPolicy.mutation(enabling: enabled),
            bundleURL: Bundle.main.bundleURL
        )
    }

    private func apply(_ mutation: LoginItemMutation) {
        do {
            try LaunchAtLoginPolicy.apply(mutation, bundleURL: Bundle.main.bundleURL)
            lastError = nil
        } catch EngineErrorCode.translocated {
            lastError = RecoveryCopy.translocated
        } catch {
            lastError = RecoveryCopy.loginItemDenied
        }
    }

    private func persistIfOnboardingComplete() {
        guard FirstRunGate.shouldPersistSettings(needsOnboarding: needsOnboarding) else {
            return
        }
        persist()
    }

    private func persist() {
        do {
            try settings.save(to: paths.settingsFile, fileManager: fileManager)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func loadOrDefault(paths: HostPaths, fileManager: FileManager) -> Settings {
        let url = paths.settingsFile
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            if let loaded = try? Settings.load(from: url) {
                return loaded
            }
        }
        return (try? Settings.makeDefault(profile: .kubernetes, host: currentHostSnapshot()))
            ?? Settings(profile: .kubernetes, cpu: 4, memoryGiB: 4, dataDiskGiB: 60)
    }

    static func currentHostSnapshot() -> HostSnapshot {
        let memoryGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let freeDiskGiB: Int
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        {
            freeDiskGiB = Int(capacity / 1_073_741_824)
        } else {
            freeDiskGiB = 100
        }
        return HostSnapshot(
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemoryGiB: max(memoryGiB, 1),
            freeDiskGiB: max(freeDiskGiB, 0),
            nestedVirtualizationSupported: SystemVirtualizationCapabilities.nestedVirtualizationSupported
        )
    }
}
