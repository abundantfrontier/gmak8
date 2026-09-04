public enum ClusterAddonMatcher {
    public static let kubernetesAddons = [
        "CoreDNS",
        "Traefik",
        "metrics-server",
        "local-path",
        "ServiceLB",
    ]

    public static let eurekaAddons = [
        "KubeVirt",
        "CDI",
        "common-instancetypes",
    ]

    public static func names(includeEureka: Bool) -> [String] {
        if includeEureka {
            return kubernetesAddons + eurekaAddons
        }
        return kubernetesAddons
    }

    public static func classify(workloadName: String) -> String? {
        let name = workloadName.lowercased()
        if name.contains("helm-install") {
            return nil
        }
        if name.contains("coredns") || name.contains("kube-dns") {
            return "CoreDNS"
        }
        if name.contains("svclb") || name.contains("klipper") {
            return "ServiceLB"
        }
        if name.contains("traefik") {
            return "Traefik"
        }
        if name.contains("metrics-server") {
            return "metrics-server"
        }
        if name.contains("local-path") {
            return "local-path"
        }
        if name.contains("virt-operator") || name.contains("virt-api") || name.contains("kubevirt") {
            return "KubeVirt"
        }
        if name.contains("cdi") {
            return "CDI"
        }
        if name.contains("common-instancetypes") || name.contains("instancetype") {
            return "common-instancetypes"
        }
        return nil
    }

    public static func addons(
        readyByName: [String: Bool],
        includeEureka: Bool
    ) -> [ClusterAddon] {
        names(includeEureka: includeEureka).map { name in
            ClusterAddon(name: name, ready: readyByName[name] ?? false)
        }
    }
}
