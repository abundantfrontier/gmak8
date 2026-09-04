import Darwin
import Foundation

public struct HostMount: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var path: String
    public var readOnly: Bool

    public init(id: String = UUID().uuidString, name: String, path: String, readOnly: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.readOnly = readOnly
    }

    public var tag: String { HostMountName.tag(for: name) }
    public var guestPath: String { HostMountName.guestPath(for: name) }
}

public enum HostMountName {
    public static let tagPrefix = "gmak8-host-"
    public static let guestRoot = "/mnt/host"
    public static let maxNameLength = 24

    public static func sanitize(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if ch == "-" || ch == "_" || ch == " " {
                if out.last != "-" {
                    out.append("-")
                }
            }
        }
        while out.hasPrefix("-") {
            out.removeFirst()
        }
        while out.hasSuffix("-") {
            out.removeLast()
        }
        if out.count > maxNameLength {
            out = String(out.prefix(maxNameLength))
            while out.hasSuffix("-") {
                out.removeLast()
            }
        }
        if out.isEmpty || out == "config" || out == "data" {
            return nil
        }
        return out
    }

    public static func tag(for name: String) -> String {
        tagPrefix + name
    }

    public static func guestPath(for name: String) -> String {
        guestRoot + "/" + name
    }
}

public enum HostUserIdentity {
    public static var uid: uid_t { getuid() }
    public static var gid: gid_t { getgid() }

    public static var display: String { "\(uid):\(gid)" }

    public static let warning =
        "Prefer root containers for hostPath, or set runAsUser / fsGroup to this uid with eyes open."
}
