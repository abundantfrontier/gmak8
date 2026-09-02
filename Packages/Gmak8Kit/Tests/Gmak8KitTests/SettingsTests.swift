import Foundation
import Testing

@testable import Gmak8Kit

struct SettingsTests {
    @Test func schemaVersionIsOne() {
        #expect(Settings.currentSchemaVersion == 1)
        let settings = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        #expect(settings.schemaVersion == 1)
        #expect(settings.clusterName == "gmak8")
        #expect(settings.setCurrentContextOnStart == false)
        #expect(settings.keepClusterRunningOnQuit == true)
        #expect(settings.telemetry == false)
    }

    @Test func roundTripPreservesFieldsAndMode0600() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-settings-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "settings.json")
        let original = Settings(
            profile: .eurekaAPIOnly,
            clusterName: "lab",
            cpu: 4,
            memoryGiB: 4,
            dataDiskGiB: 60,
            setCurrentContextOnStart: true,
            keepClusterRunningOnQuit: false,
            telemetry: true
        )
        try original.save(to: url)

        let loaded = try Settings.load(from: url)
        #expect(loaded == original)
        #expect(loaded.schemaVersion == Settings.currentSchemaVersion)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(json.contains("\"schemaVersion\""))
        #expect(json.contains("\"eurekaAPIOnly\""))
    }

    @Test func loadRejectsUnsupportedSchemaVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-settings-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "settings.json")
        var settings = Settings(profile: .kubernetes, cpu: 2, memoryGiB: 4, dataDiskGiB: 60)
        settings.schemaVersion = 99
        try settings.save(to: url)

        #expect(throws: SettingsError.unsupportedSchemaVersion(99)) {
            try Settings.load(from: url)
        }
    }

    @Test func makeDefaultUsesProfileResources() throws {
        let host = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 16,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: false
        )
        let settings = try Settings.makeDefault(profile: .kubernetes, host: host)
        #expect(settings.schemaVersion == 1)
        #expect(settings.profile == .kubernetes)
        #expect(settings.cpu == 4)
        #expect(settings.memoryGiB == 6)
        #expect(settings.dataDiskGiB == 60)
    }

    @Test func makeDefaultThrowsStructuredEurekaRefusal() {
        let host = HostSnapshot(
            processorCount: 8,
            physicalMemoryGiB: 8,
            freeDiskGiB: 100,
            nestedVirtualizationSupported: true
        )
        #expect(throws: ProfileRefusal.insufficientMemory(requiredGiB: 18, availableGiB: 8)) {
            try Settings.makeDefault(profile: .eureka, host: host)
        }
    }
}
