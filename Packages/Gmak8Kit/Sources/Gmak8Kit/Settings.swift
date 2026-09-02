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
    public var launchAtLogin: Bool
    public var telemetry: Bool
    public var publishNodePorts: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        profile: Profile,
        clusterName: String = "gmak8",
        cpu: Int,
        memoryGiB: Int,
        dataDiskGiB: Int,
        setCurrentContextOnStart: Bool = false,
        keepClusterRunningOnQuit: Bool = true,
        launchAtLogin: Bool = false,
        telemetry: Bool = false,
        publishNodePorts: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.clusterName = clusterName
        self.cpu = cpu
        self.memoryGiB = memoryGiB
        self.dataDiskGiB = dataDiskGiB
        self.setCurrentContextOnStart = setCurrentContextOnStart
        self.keepClusterRunningOnQuit = keepClusterRunningOnQuit
        self.launchAtLogin = launchAtLogin
        self.telemetry = telemetry
        self.publishNodePorts = publishNodePorts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profile
        case clusterName
        case cpu
        case memoryGiB
        case dataDiskGiB
        case setCurrentContextOnStart
        case keepClusterRunningOnQuit
        case launchAtLogin
        case telemetry
        case publishNodePorts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        profile = try container.decode(Profile.self, forKey: .profile)
        clusterName = try container.decode(String.self, forKey: .clusterName)
        cpu = try container.decode(Int.self, forKey: .cpu)
        memoryGiB = try container.decode(Int.self, forKey: .memoryGiB)
        dataDiskGiB = try container.decode(Int.self, forKey: .dataDiskGiB)
        setCurrentContextOnStart = try container.decode(Bool.self, forKey: .setCurrentContextOnStart)
        keepClusterRunningOnQuit = try container.decode(Bool.self, forKey: .keepClusterRunningOnQuit)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        telemetry = try container.decode(Bool.self, forKey: .telemetry)
        publishNodePorts = try container.decodeIfPresent(Bool.self, forKey: .publishNodePorts) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profile, forKey: .profile)
        try container.encode(clusterName, forKey: .clusterName)
        try container.encode(cpu, forKey: .cpu)
        try container.encode(memoryGiB, forKey: .memoryGiB)
        try container.encode(dataDiskGiB, forKey: .dataDiskGiB)
        try container.encode(setCurrentContextOnStart, forKey: .setCurrentContextOnStart)
        try container.encode(keepClusterRunningOnQuit, forKey: .keepClusterRunningOnQuit)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(telemetry, forKey: .telemetry)
        try container.encode(publishNodePorts, forKey: .publishNodePorts)
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
