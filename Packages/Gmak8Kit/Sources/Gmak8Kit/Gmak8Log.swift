import os

public enum Gmak8Log {
    public static let subsystem = Gmak8Kit.bundleIdentifier

    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let core = Logger(subsystem: subsystem, category: "core")
    public static let vm = Logger(subsystem: subsystem, category: "vm")
    public static let net = Logger(subsystem: subsystem, category: "net")
    public static let k8s = Logger(subsystem: subsystem, category: "k8s")
    public static let kubevirt = Logger(subsystem: subsystem, category: "kubevirt")
}
