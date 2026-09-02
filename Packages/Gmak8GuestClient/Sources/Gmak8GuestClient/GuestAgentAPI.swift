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
