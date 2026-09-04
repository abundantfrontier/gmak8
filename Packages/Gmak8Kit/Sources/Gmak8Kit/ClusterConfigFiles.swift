import Foundation

public enum ClusterConfigFiles {
    public static func write(
        directory: URL,
        settings: Settings,
        proxy: GuestProxyEnv,
        password: (String) -> String? = { RegistryKeychain.password(host: $0) },
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try K3sConfig.writeHostFile(
            directory: directory,
            disable: settings.k3sDisable,
            httpsListenPort: settings.apiPort,
            fileManager: fileManager
        )
        try AtomicFileReplace.write(
            Data(proxy.fileContents.utf8),
            to: directory.appending(path: "proxy.env"),
            posixPermissions: 0o600,
            fileManager: fileManager
        )
        let registries = RegistriesFile.render(
            userYAML: settings.registriesYAML,
            hosts: settings.registryHosts,
            password: password
        )
        let registriesURL = directory.appending(path: "registries.yaml")
        if registries.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if fileManager.fileExists(atPath: registriesURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: registriesURL)
            }
        } else {
            try AtomicFileReplace.write(
                Data(registries.utf8),
                to: registriesURL,
                posixPermissions: 0o600,
                fileManager: fileManager
            )
        }
        let mounts = HostMountList(
            items: settings.hostMounts.map { mount in
                HostMountSpec(
                    name: mount.name,
                    tag: mount.tag,
                    path: mount.guestPath,
                    readOnly: mount.readOnly
                )
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileReplace.write(
            try encoder.encode(mounts),
            to: directory.appending(path: "host-mounts.json"),
            posixPermissions: 0o600,
            fileManager: fileManager
        )
    }
}

public struct HostMountList: Codable, Equatable, Sendable {
    public var items: [HostMountSpec]

    public init(items: [HostMountSpec] = []) {
        self.items = items
    }
}

public struct HostMountSpec: Codable, Equatable, Sendable {
    public var name: String
    public var tag: String
    public var path: String
    public var readOnly: Bool

    public init(name: String, tag: String, path: String, readOnly: Bool) {
        self.name = name
        self.tag = tag
        self.path = path
        self.readOnly = readOnly
    }

    enum CodingKeys: String, CodingKey {
        case name
        case tag
        case path
        case readOnly = "read_only"
    }
}
