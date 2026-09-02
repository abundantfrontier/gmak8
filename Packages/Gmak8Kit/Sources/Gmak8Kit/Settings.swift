import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var profile: Profile
    public var clusterName: String
    public var cpu: Int
    public var memoryGiB: Int
    public var dataDiskGiB: Int
    public var setCurrentContextOnStart: Bool
    public var keepClusterRunningOnQuit: Bool
    public var telemetry: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        profile: Profile,
        clusterName: String = "gmak8",
        cpu: Int,
        memoryGiB: Int,
        dataDiskGiB: Int,
        setCurrentContextOnStart: Bool = false,
        keepClusterRunningOnQuit: Bool = true,
        telemetry: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.clusterName = clusterName
        self.cpu = cpu
        self.memoryGiB = memoryGiB
        self.dataDiskGiB = dataDiskGiB
        self.setCurrentContextOnStart = setCurrentContextOnStart
        self.keepClusterRunningOnQuit = keepClusterRunningOnQuit
        self.telemetry = telemetry
    }

    public static func makeDefault(profile: Profile = .kubernetes, host: HostSnapshot) throws -> Settings {
        switch profile.resourceDefaults(host: host) {
        case .accepted(let resources):
            return Settings(
                profile: profile,
                cpu: resources.cpu,
                memoryGiB: resources.memoryGiB,
                dataDiskGiB: resources.dataDiskGiB
            )
        case .refused(let refusal):
            throw refusal
        }
    }

    public static func load(from url: URL) throws -> Settings {
        let data = try Data(contentsOf: url)
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        guard settings.schemaVersion == currentSchemaVersion else {
            throw SettingsError.unsupportedSchemaVersion(settings.schemaVersion)
        }
        return settings
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeOwnerReadWriteAtomically(data, to: url, fileManager: fileManager)
    }
}

/// chmod 0600 on a sibling temp, then replace, so the published path is never world-readable.
private func writeOwnerReadWriteAtomically(_ data: Data, to url: URL, fileManager: FileManager) throws {
    let temp = url.deletingLastPathComponent().appending(
        path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    do {
        try data.write(to: temp, options: .withoutOverwriting)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: temp.path(percentEncoded: false)
        )
        _ = try fileManager.replaceItemAt(
            url,
            withItemAt: temp,
            backupItemName: nil,
            options: .usingNewMetadataOnly
        )
    } catch {
        try? fileManager.removeItem(at: temp)
        throw error
    }
}

public enum SettingsError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}
