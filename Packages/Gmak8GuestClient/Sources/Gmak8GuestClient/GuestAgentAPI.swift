import Foundation

public enum DiskMountState: String, Codable, Equatable, Sendable {
    case mounted
    case unmounted
}

public struct GuestHealth: Codable, Equatable, Sendable {
    public var ok: Bool

    public init(ok: Bool) {
        self.ok = ok
    }
}

public struct GuestDisks: Codable, Equatable, Sendable {
    public var gmak8Data: DiskMountState
    public var kiteData: DiskMountState
    public var mountpoint: String
    public var label: String
    public var bytesTotal: UInt64
    public var bytesFree: UInt64

    public var isDataMounted: Bool { gmak8Data == .mounted }

    public init(
        gmak8Data: DiskMountState,
        kiteData: DiskMountState,
        mountpoint: String,
        label: String,
        bytesTotal: UInt64,
        bytesFree: UInt64
    ) {
        self.gmak8Data = gmak8Data
        self.kiteData = kiteData
        self.mountpoint = mountpoint
        self.label = label
        self.bytesTotal = bytesTotal
        self.bytesFree = bytesFree
    }

    enum CodingKeys: String, CodingKey {
        case gmak8Data = "gmak8_data"
        case kiteData = "kite_data"
        case mountpoint
        case label
        case bytesTotal = "bytes_total"
        case bytesFree = "bytes_free"
    }
}

public struct GuestSSHD: Codable, Equatable, Sendable {
    public var running: Bool

    public init(running: Bool = false) {
        self.running = running
    }
}

public struct GuestKubeVirt: Codable, Equatable, Sendable {
    public var installed: Bool
    public var phase: String
    public var u1Nano: Bool
    public var kvm: Bool

    public init(installed: Bool = false, phase: String = "", u1Nano: Bool = false, kvm: Bool = false) {
        self.installed = installed
        self.phase = phase
        self.u1Nano = u1Nano
        self.kvm = kvm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        phase = try container.decodeIfPresent(String.self, forKey: .phase) ?? ""
        u1Nano = try container.decodeIfPresent(Bool.self, forKey: .u1Nano) ?? false
        kvm = try container.decodeIfPresent(Bool.self, forKey: .kvm) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case installed
        case phase
        case u1Nano = "u1_nano"
        case kvm
    }
}

public struct GuestKVM: Codable, Equatable, Sendable {
    public var kvm: Bool

    public init(kvm: Bool) {
        self.kvm = kvm
    }
}

public struct GuestK3s: Codable, Equatable, Sendable {
    public var active: Bool
    public var version: String?
    public var dataDirMinor: String?
    public var dataDirExists: Bool

    public init(active: Bool, version: String? = nil, dataDirMinor: String? = nil, dataDirExists: Bool) {
        self.active = active
        self.version = version
        self.dataDirMinor = dataDirMinor
        self.dataDirExists = dataDirExists
    }

    enum CodingKeys: String, CodingKey {
        case active
        case version
        case dataDirMinor = "data_dir_minor"
        case dataDirExists = "data_dir_exists"
    }
}

public struct GuestNode: Codable, Equatable, Sendable {
    public var ready: Bool
    public var name: String?

    public init(ready: Bool, name: String? = nil) {
        self.ready = ready
        self.name = name
    }
}

public struct GuestServiceList: Codable, Equatable, Sendable {
    public var items: [GuestService]

    public init(items: [GuestService] = []) {
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GuestService].self, forKey: .items) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }
}

public struct GuestService: Codable, Equatable, Sendable {
    public var namespace: String
    public var name: String
    public var type: String
    public var ports: [GuestServicePort]

    public init(namespace: String, name: String, type: String, ports: [GuestServicePort]) {
        self.namespace = namespace
        self.name = name
        self.type = type
        self.ports = ports
    }
}

public struct GuestServicePort: Codable, Equatable, Sendable {
    public var name: String?
    public var port: Int
    public var nodePort: Int?
    public var protocolName: String?

    public init(name: String? = nil, port: Int, nodePort: Int? = nil, protocolName: String? = nil) {
        self.name = name
        self.port = port
        self.nodePort = nodePort
        self.protocolName = protocolName
    }

    enum CodingKeys: String, CodingKey {
        case name
        case port
        case nodePort
        case protocolName = "protocol"
    }
}

public struct GuestOK: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?

    public init(ok: Bool, error: String? = nil) {
        self.ok = ok
        self.error = error
    }
}

public struct GuestAirgap: Codable, Equatable, Sendable {
    public var present: Bool
    public var files: [String]
    public var bytes: UInt64

    public init(present: Bool, files: [String] = [], bytes: UInt64 = 0) {
        self.present = present
        self.files = files
        self.bytes = bytes
    }
}

public struct GuestImage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var refs: [String]
    public var sizeBytes: Int64
    public var system: Bool

    public init(id: String, refs: [String] = [], sizeBytes: Int64 = 0, system: Bool = false) {
        self.id = id
        self.refs = refs
        self.sizeBytes = sizeBytes
        self.system = system
    }

    enum CodingKeys: String, CodingKey {
        case id
        case refs
        case sizeBytes = "size_bytes"
        case system
    }
}

public struct GuestImageList: Codable, Equatable, Sendable {
    public var items: [GuestImage]

    public init(items: [GuestImage] = []) {
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GuestImage].self, forKey: .items) ?? []
    }
}

public struct GuestImageImport: Codable, Equatable, Sendable {
    public var digest: String
    public var refs: [String]

    public init(digest: String, refs: [String] = []) {
        self.digest = digest
        self.refs = refs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        digest = try container.decodeIfPresent(String.self, forKey: .digest) ?? ""
        refs = try container.decodeIfPresent([String].self, forKey: .refs) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case digest
        case refs
    }
}

public struct GuestHostMountList: Codable, Equatable, Sendable {
    public var items: [GuestHostMount]

    public init(items: [GuestHostMount] = []) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GuestHostMount].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

public struct GuestHostMount: Codable, Equatable, Sendable {
    public var name: String
    public var tag: String
    public var path: String
    public var readOnly: Bool
    public var mounted: Bool
    public var uid: UInt32
    public var gid: UInt32

    public init(
        name: String,
        tag: String,
        path: String,
        readOnly: Bool = false,
        mounted: Bool = false,
        uid: UInt32 = 0,
        gid: UInt32 = 0
    ) {
        self.name = name
        self.tag = tag
        self.path = path
        self.readOnly = readOnly
        self.mounted = mounted
        self.uid = uid
        self.gid = gid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        tag = try container.decode(String.self, forKey: .tag)
        path = try container.decode(String.self, forKey: .path)
        readOnly = try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        mounted = try container.decodeIfPresent(Bool.self, forKey: .mounted) ?? false
        uid = try container.decodeIfPresent(UInt32.self, forKey: .uid) ?? 0
        gid = try container.decodeIfPresent(UInt32.self, forKey: .gid) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case name
        case tag
        case path
        case readOnly = "read_only"
        case mounted
        case uid
        case gid
    }
}

public struct GuestImagePrune: Codable, Equatable, Sendable {
    public var deleted: [String]

    public init(deleted: [String] = []) {
        self.deleted = deleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deleted = try container.decodeIfPresent([String].self, forKey: .deleted) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case deleted
    }
}

public enum GuestTime: Equatable, Sendable {
    case unix(Int64)
    case rfc3339(String)
    case date(Date)

    public func encodeBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch self {
        case .unix(let seconds):
            return try encoder.encode(UnixTimeBody(unix: seconds))
        case .rfc3339(let value):
            return try encoder.encode(RFC3339TimeBody(rfc3339: value))
        case .date(let date):
            return try encoder.encode(UnixTimeBody(unix: Int64(date.timeIntervalSince1970)))
        }
    }
}

struct UnixTimeBody: Codable, Equatable {
    var unix: Int64
}

struct RFC3339TimeBody: Codable, Equatable {
    var rfc3339: String
}

public enum GuestAgentError: Error, Equatable, LocalizedError, Sendable {
    case httpStatus(Int, String?)
    case decode(String)
    case connectFailed(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let message):
            return message ?? "guest agent HTTP \(code)"
        case .decode(let message):
            return "guest agent decode: \(message)"
        case .connectFailed(let message):
            return "guest agent connect: \(message)"
        case .io(let message):
            return "guest agent io: \(message)"
        }
    }
}
