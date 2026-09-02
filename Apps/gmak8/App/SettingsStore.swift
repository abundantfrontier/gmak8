import Combine
import Foundation
import Gmak8Kit
import Gmak8XPC

@MainActor
final class SettingsStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var settings: Settings
    @Published var lastError: String?

    private let paths: HostPaths
    private let fileManager: FileManager

    init(paths: HostPaths = .current(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.settings = SettingsStore.loadOrDefault(paths: paths, fileManager: fileManager)
    }

    var keepClusterRunningOnQuit: Bool {
        settings.keepClusterRunningOnQuit
    }

    func setKeepClusterRunningOnQuit(_ value: Bool) {
        settings.keepClusterRunningOnQuit = value
        persist()
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            try applyLaunchAtLogin(value)
            settings.launchAtLogin = value
            persist()
            lastError = nil
        } catch EngineErrorCode.translocated {
            lastError = "Move gmak8 to /Applications and re-open."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyLaunchAtLoginIfNeeded() {
        guard settings.launchAtLogin else {
            return
        }
        do {
            try applyLaunchAtLogin(true)
            lastError = nil
        } catch EngineErrorCode.translocated {
            lastError = "Move gmak8 to /Applications and re-open."
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) throws {
        let bundleURL = Bundle.main.bundleURL
        if enabled {
            try ExtraLoginItem.register(bundleURL: bundleURL)
            try CoreLaunchAgent.register(bundleURL: bundleURL)
        } else {
            try ExtraLoginItem.unregister()
            try CoreLaunchAgent.unregister()
        }
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
            nestedVirtualizationSupported: false
        )
    }
}
