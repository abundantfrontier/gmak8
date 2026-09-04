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
    /// Visible inbox for guest disks and k3s packs. Empty means `~/gmak8`.
    public var libraryFolderPath: String
    /// Checkout that contains `guest/mkosi`. Empty means auto-detect.
    public var sourceRepoPath: String
    public var startClusterAtLogin: Bool
    public var balloonEnabled: Bool
    public var kubeVirtAddon: Bool
    public var disableTraefik: Bool
    public var disableServiceLB: Bool
    public var disableLocalStorage: Bool
    public var disableMetricsServer: Bool
    public var apiPort: Int
    public var guestSSHDebug: Bool
    public var registriesYAML: String
    public var registryHosts: [RegistryHost]
    public var hostMounts: [HostMount]

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
        publishNodePorts: Bool = true,
        libraryFolderPath: String = "",
        sourceRepoPath: String = "",
        startClusterAtLogin: Bool = false,
        balloonEnabled: Bool = false,
        kubeVirtAddon: Bool = false,
        disableTraefik: Bool = false,
        disableServiceLB: Bool = false,
        disableLocalStorage: Bool = false,
        disableMetricsServer: Bool = false,
        apiPort: Int = 6443,
        guestSSHDebug: Bool = false,
        registriesYAML: String = "",
        registryHosts: [RegistryHost] = [],
        hostMounts: [HostMount] = []
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
        self.telemetry = false
        self.publishNodePorts = publishNodePorts
        self.libraryFolderPath = libraryFolderPath
        self.sourceRepoPath = sourceRepoPath
        self.startClusterAtLogin = startClusterAtLogin
        self.balloonEnabled = false
        self.kubeVirtAddon = kubeVirtAddon || profile != .kubernetes
        self.disableTraefik = disableTraefik
        self.disableServiceLB = disableServiceLB
        self.disableLocalStorage = disableLocalStorage
        self.disableMetricsServer = disableMetricsServer
        self.apiPort = apiPort
        self.guestSSHDebug = guestSSHDebug
        self.registriesYAML = registriesYAML
        self.registryHosts = registryHosts
        self.hostMounts = hostMounts
    }

    public var kubeVirtEnabled: Bool {
        profile != .kubernetes || kubeVirtAddon
    }

    public var k3sDisable: [String] {
        K3sConfig.disableList(
            traefik: disableTraefik,
            servicelb: disableServiceLB,
            localStorage: disableLocalStorage,
            metricsServer: disableMetricsServer
        )
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
        case libraryFolderPath
        case sourceRepoPath
        case startClusterAtLogin
        case balloonEnabled
        case kubeVirtAddon
        case disableTraefik
        case disableServiceLB
        case disableLocalStorage
        case disableMetricsServer
        case apiPort
        case guestSSHDebug
        case registriesYAML
        case registryHosts
        case hostMounts
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
        telemetry = false
        publishNodePorts = try container.decodeIfPresent(Bool.self, forKey: .publishNodePorts) ?? true
        libraryFolderPath = try container.decodeIfPresent(String.self, forKey: .libraryFolderPath) ?? ""
        sourceRepoPath = try container.decodeIfPresent(String.self, forKey: .sourceRepoPath) ?? ""
        startClusterAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startClusterAtLogin) ?? false
        balloonEnabled = false
        kubeVirtAddon = try container.decodeIfPresent(Bool.self, forKey: .kubeVirtAddon) ?? (profile != .kubernetes)
        disableTraefik = try container.decodeIfPresent(Bool.self, forKey: .disableTraefik) ?? false
        disableServiceLB = try container.decodeIfPresent(Bool.self, forKey: .disableServiceLB) ?? false
        disableLocalStorage = try container.decodeIfPresent(Bool.self, forKey: .disableLocalStorage) ?? false
        disableMetricsServer = try container.decodeIfPresent(Bool.self, forKey: .disableMetricsServer) ?? false
        apiPort = try container.decodeIfPresent(Int.self, forKey: .apiPort) ?? 6443
        guestSSHDebug = try container.decodeIfPresent(Bool.self, forKey: .guestSSHDebug) ?? false
        registriesYAML = try container.decodeIfPresent(String.self, forKey: .registriesYAML) ?? ""
        registryHosts = try container.decodeIfPresent([RegistryHost].self, forKey: .registryHosts) ?? []
        hostMounts = try container.decodeIfPresent([HostMount].self, forKey: .hostMounts) ?? []
        if profile != .kubernetes {
            kubeVirtAddon = true
        }
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
        try container.encode(false, forKey: .telemetry)
        try container.encode(publishNodePorts, forKey: .publishNodePorts)
        try container.encode(libraryFolderPath, forKey: .libraryFolderPath)
        try container.encode(sourceRepoPath, forKey: .sourceRepoPath)
        try container.encode(startClusterAtLogin, forKey: .startClusterAtLogin)
        try container.encode(false, forKey: .balloonEnabled)
        try container.encode(profile != .kubernetes || kubeVirtAddon, forKey: .kubeVirtAddon)
        try container.encode(disableTraefik, forKey: .disableTraefik)
        try container.encode(disableServiceLB, forKey: .disableServiceLB)
        try container.encode(disableLocalStorage, forKey: .disableLocalStorage)
        try container.encode(disableMetricsServer, forKey: .disableMetricsServer)
        try container.encode(apiPort, forKey: .apiPort)
        try container.encode(guestSSHDebug, forKey: .guestSSHDebug)
        try container.encode(registriesYAML, forKey: .registriesYAML)
        try container.encode(registryHosts, forKey: .registryHosts)
        try container.encode(hostMounts, forKey: .hostMounts)
    }

    public func libraryRoot(home: URL) -> URL {
        AssetLibrary.resolvedRoot(libraryFolderPath: libraryFolderPath, home: home)
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
        try AtomicFileReplace.write(data, to: url, posixPermissions: 0o600, fileManager: fileManager)
    }
}

public enum SettingsError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}
