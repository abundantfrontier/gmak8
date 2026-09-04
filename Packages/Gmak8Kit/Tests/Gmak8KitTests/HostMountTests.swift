import Foundation
import Testing

@testable import Gmak8Kit

struct HostMountTests {
    @Test func sanitizeRejectsEmptyAndReserved() {
        #expect(HostMountName.sanitize("") == nil)
        #expect(HostMountName.sanitize("***") == nil)
        #expect(HostMountName.sanitize("config") == nil)
        #expect(HostMountName.sanitize("data") == nil)
        #expect(HostMountName.sanitize("My Projects") == "my-projects")
        #expect(HostMountName.sanitize("Foo_Bar") == "foo-bar")
    }

    @Test func tagAndGuestPath() {
        let mount = HostMount(name: "src", path: "/Users/kb/src")
        #expect(mount.tag == "gmak8-host-src")
        #expect(mount.guestPath == "/mnt/host/src")
        #expect(HostMountName.tag(for: "src").count <= 36)
        let long = String(repeating: "a", count: 40)
        let clipped = HostMountName.sanitize(long)
        #expect(clipped == String(repeating: "a", count: HostMountName.maxNameLength))
        if let clipped {
            #expect(HostMountName.tag(for: clipped).count <= 36)
        }
    }

    @Test func hostUIDDisplayMatchesGetuid() {
        #expect(HostUserIdentity.display.contains(":"))
        #expect(HostUserIdentity.warning.contains("runAsUser"))
        #expect(SettingsCopy.noHomeShare.contains("$HOME"))
    }
}

struct SystemProxyTests {
    @Test func buildsProxyEnvFromSCDynamicStoreShape() {
        let env = SystemProxy.fromProxySettings([
            "HTTPEnable": 1,
            "HTTPProxy": "proxy.example.com",
            "HTTPPort": 8080,
            "HTTPSEnable": 1,
            "HTTPSProxy": "proxy.example.com",
            "HTTPSPort": 8443,
        ])
        #expect(env.httpProxy == "http://proxy.example.com:8080")
        #expect(env.httpsProxy == "https://proxy.example.com:8443")
        #expect(env.noProxy.contains("127.0.0.1"))
        #expect(env.noProxy.contains("10.42.0.0/16"))
        let file = env.fileContents
        #expect(file.contains("HTTP_PROXY=http://proxy.example.com:8080"))
        #expect(file.contains("NO_PROXY="))
    }

    @Test func disabledProxyIsEmpty() {
        let env = SystemProxy.fromProxySettings(["HTTPEnable": 0])
        #expect(env.httpProxy == nil)
        #expect(env.fileContents.contains("NO_PROXY="))
    }
}

struct ClusterConfigFilesTests {
    @Test func writesK3sDisableProxyAndHostMounts() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-config-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var settings = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        settings.disableTraefik = true
        settings.hostMounts = [HostMount(name: "src", path: "/tmp/src")]
        settings.registriesYAML = "mirrors: {}"
        try ClusterConfigFiles.write(
            directory: root,
            settings: settings,
            proxy: GuestProxyEnv(httpProxy: "http://127.0.0.1:3128"),
            password: { _ in nil }
        )
        let yaml = try String(contentsOf: root.appending(path: "k3s/config.yaml"), encoding: .utf8)
        #expect(yaml.contains("disable:"))
        #expect(yaml.contains("traefik"))
        #expect(K3sConfig.hasDataDiskLocalPath(yaml))
        #expect(!yaml.contains("disable-helm-controller:"))
        let proxy = try String(contentsOf: root.appending(path: "proxy.env"), encoding: .utf8)
        #expect(proxy.contains("HTTP_PROXY=http://127.0.0.1:3128"))
        let mounts = try JSONDecoder().decode(
            HostMountList.self,
            from: try Data(contentsOf: root.appending(path: "host-mounts.json"))
        )
        #expect(mounts.items.map(\.tag) == ["gmak8-host-src"])
        #expect(mounts.items[0].path == "/mnt/host/src")
        let proxyMode =
            try FileManager.default.attributesOfItem(
                atPath: root.appending(path: "proxy.env").path(percentEncoded: false)
            )[.posixPermissions] as? NSNumber
        #expect(proxyMode?.intValue == 0o600)
    }

    @Test func registriesFileStripsPasswordsFromUserYAML() {
        let rendered = RegistriesFile.render(
            userYAML: "mirrors: {}\npassword: hunter2",
            hosts: [RegistryHost(host: "ghcr.io", username: "me")],
            password: { _ in "secret" }
        )
        #expect(!rendered.contains("hunter2"))
        #expect(rendered.contains("password: secret"))
        #expect(rendered.contains("ghcr.io"))
    }

    @Test func registriesFileIsMode0600() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-config-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var settings = Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
        settings.registryHosts = [RegistryHost(host: "ghcr.io", username: "me")]
        try ClusterConfigFiles.write(
            directory: root,
            settings: settings,
            proxy: GuestProxyEnv(),
            password: { _ in "secret" }
        )
        let path = root.appending(path: "registries.yaml").path(percentEncoded: false)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let body = try String(contentsOf: root.appending(path: "registries.yaml"), encoding: .utf8)
        #expect(body.contains("password: secret"))
    }
}
