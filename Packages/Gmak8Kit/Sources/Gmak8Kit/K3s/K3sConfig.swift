import Foundation

/// Host-generated k3s config written onto virtio-fs tag `gmak8-config`.
public enum K3sConfig {
    public static let virtioFSTag = "gmak8-config"
    public static let guestMountPoint = "/mnt/config"
    public static let yaml = """
        # k3s config template. Admin kubeconfig stays /etc/rancher/k3s/k3s.yaml.
        # Do not set disable-helm-controller (Traefik/metrics-server are HelmCharts).
        # Do not set a custom write-kubeconfig path.
        data-dir: /mnt/data/rancher
        default-local-storage-path: /mnt/data/local-path
        cluster-cidr: 10.42.0.0/16
        service-cidr: 10.43.0.0/16
        cluster-dns: 10.43.0.10
        tls-san:
          - 127.0.0.1
          - localhost
          - gmak8
          - gmak8.internal
          - 192.168.127.2
        node-name: gmak8
        https-listen-port: 6443

        """

    public static let allowedDisable = ["traefik", "servicelb", "local-storage", "metrics-server"]
    public static let eurekaLocalPath = "/mnt/data/local-path"

    public static func disableList(
        traefik: Bool,
        servicelb: Bool,
        localStorage: Bool,
        metricsServer: Bool
    ) -> [String] {
        var flags: [String] = []
        if traefik { flags.append("traefik") }
        if servicelb { flags.append("servicelb") }
        if localStorage { flags.append("local-storage") }
        if metricsServer { flags.append("metrics-server") }
        return flags
    }

    public static func rendered(disable: [String] = [], httpsListenPort: Int = 6443) -> String {
        var text = yaml.replacingOccurrences(
            of: "https-listen-port: 6443", with: "https-listen-port: \(httpsListenPort)")
        let flags = disable.filter { allowedDisable.contains($0) }
        if !flags.isEmpty {
            text += "disable:\n"
            for flag in flags {
                text += "  - \(flag)\n"
            }
        }
        return text
    }

    public static func hasDataDiskLocalPath(_ text: String) -> Bool {
        text.contains("default-local-storage-path: \(eurekaLocalPath)")
    }

    public static func writeHostFile(
        directory: URL,
        disable: [String] = [],
        httpsListenPort: Int = 6443,
        fileManager: FileManager = .default
    ) throws {
        let dest = directory.appending(path: "k3s", directoryHint: .isDirectory).appending(path: "config.yaml")
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rendered(disable: disable, httpsListenPort: httpsListenPort).write(
            to: dest, atomically: true, encoding: .utf8)
    }
}
