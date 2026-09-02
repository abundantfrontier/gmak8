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

public struct GuestOK: Codable, Equatable, Sendable {
    public var ok: Bool
    public var error: String?

    public init(ok: Bool, error: String? = nil) {
        self.ok = ok
        self.error = error
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

public enum GuestAgentError: Error, Equatable, Sendable {
    case httpStatus(Int, String?)
    case decode(String)
    case connectFailed(String)
    case io(String)
}
