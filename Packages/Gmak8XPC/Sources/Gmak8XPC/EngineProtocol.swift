import Foundation

public enum ClusterState: String, Codable, Equatable, Sendable, CaseIterable {
    case stopped
    case starting
    case running
    case degraded
    case paused
    case stopping
    case failed
}

public enum EngineErrorCode: String, Error, Codable, Equatable, Sendable {
    case conflict
    case confirmationRequired = "confirmation_required"
    case translocated
    case locked
    case virtualizationUnsupported = "virtualization_unsupported"
    case unauthorized
    case unknownOp = "unknown_op"
    case invalidRequest = "invalid_request"
}

public enum EngineRequest: Equatable, Sendable {
    case start
    case stop
    case prepareUpdate
    case reset(force: Bool)
    case status
    case subscribe
    case loadImage(path: String)
    case imageList
    case imagePrune
}

public enum EngineReply: Equatable, Sendable {
    case ok
    case error(EngineErrorCode)
}

public enum LogSource: String, Codable, Equatable, Sendable {
    case engine
    case serial
}

public struct VMMetrics: Equatable, Sendable, Codable {
    public var cpu: Double
    public var ramUsed: Double
    public var ramCap: Double
    public var diskUsed: Double
    public var diskCap: Double

    public init(
        cpu: Double = 0,
        ramUsed: Double = 0,
        ramCap: Double = 0,
        diskUsed: Double = 0,
        diskCap: Double = 0
    ) {
        self.cpu = cpu
        self.ramUsed = ramUsed
        self.ramCap = ramCap
        self.diskUsed = diskUsed
        self.diskCap = diskCap
    }
}

public enum PublishedPortCollision: String, Codable, Equatable, Sendable {
    case published
    case remapped
    case collision
    case forbidden
    case capped
}

public struct PublishedPort: Equatable, Sendable, Codable {
    public var service: String
    public var namespace: String?
    public var port: Int
    public var nodePort: Int
    public var hostPort: Int
    public var guestPort: Int
    public var hostURL: String
    public var collision: PublishedPortCollision

    public init(
        service: String,
        namespace: String? = nil,
        port: Int = 0,
        nodePort: Int = 0,
        hostPort: Int,
        guestPort: Int,
        hostURL: String? = nil,
        collision: PublishedPortCollision = .published
    ) {
        self.service = service
        self.namespace = namespace
        self.port = port == 0 ? guestPort : port
        self.nodePort = nodePort == 0 ? guestPort : nodePort
        self.hostPort = hostPort
        self.guestPort = guestPort
        self.hostURL = hostURL ?? "http://127.0.0.1:\(hostPort)"
        self.collision = collision
    }

    public static func loopback(
        service: String,
        namespace: String? = nil,
        port: Int,
        nodePort: Int,
        hostPort: Int,
        guestPort: Int,
        scheme: String,
        preferredHostPort: Int
    ) -> PublishedPort {
        PublishedPort(
            service: service,
            namespace: namespace,
            port: port,
            nodePort: nodePort,
            hostPort: hostPort,
            guestPort: guestPort,
            hostURL: "\(scheme)://127.0.0.1:\(hostPort)",
            collision: hostPort == preferredHostPort ? .published : .remapped
        )
    }

    enum CodingKeys: String, CodingKey {
        case service
        case namespace
        case port
        case nodePort
        case hostPort
        case guestPort
        case hostURL
        case collision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        service = try container.decode(String.self, forKey: .service)
        namespace = try container.decodeIfPresent(String.self, forKey: .namespace)
        hostPort = try container.decode(Int.self, forKey: .hostPort)
        guestPort = try container.decode(Int.self, forKey: .guestPort)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? guestPort
        nodePort = try container.decodeIfPresent(Int.self, forKey: .nodePort) ?? guestPort
        hostURL =
            try container.decodeIfPresent(String.self, forKey: .hostURL) ?? "http://127.0.0.1:\(hostPort)"
        collision = try container.decodeIfPresent(PublishedPortCollision.self, forKey: .collision) ?? .published
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(service, forKey: .service)
        try container.encodeIfPresent(namespace, forKey: .namespace)
        try container.encode(port, forKey: .port)
        try container.encode(nodePort, forKey: .nodePort)
        try container.encode(hostPort, forKey: .hostPort)
        try container.encode(guestPort, forKey: .guestPort)
        try container.encode(hostURL, forKey: .hostURL)
        try container.encode(collision, forKey: .collision)
    }
}

public struct ImageJobStatus: Equatable, Sendable, Codable {
    public var bytesReceived: Int64
    public var bytesTotal: Int64?
    public var importing: Bool

    public init(bytesReceived: Int64, bytesTotal: Int64? = nil, importing: Bool = false) {
        self.bytesReceived = bytesReceived
        self.bytesTotal = bytesTotal
        self.importing = importing
    }

    enum CodingKeys: String, CodingKey {
        case bytesReceived
        case bytesTotal
        case importing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bytesReceived = try container.decode(Int64.self, forKey: .bytesReceived)
        bytesTotal = try container.decodeIfPresent(Int64.self, forKey: .bytesTotal)
        importing = try container.decodeIfPresent(Bool.self, forKey: .importing) ?? false
    }
}

public struct NodeImage: Equatable, Sendable, Codable, Identifiable, Hashable {
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

    public var displayName: String {
        refs.first ?? id
    }
}

public struct NodeImageList: Equatable, Sendable, Codable {
    public var items: [NodeImage]

    public init(items: [NodeImage] = []) {
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([NodeImage].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

public struct EngineStatus: Equatable, Sendable {
    public var state: ClusterState
    public var step: String?
    public var apiEndpoint: String?
    public var vm: VMMetrics?
    public var nestedVirt: Bool
    public var kvmPresent: Bool?
    public var lastError: String?
    public var publishedPorts: [PublishedPort]
    public var imageJob: ImageJobStatus?

    public init(
        state: ClusterState,
        step: String? = nil,
        apiEndpoint: String? = nil,
        vm: VMMetrics? = VMMetrics(),
        nestedVirt: Bool = false,
        kvmPresent: Bool? = nil,
        lastError: String? = nil,
        publishedPorts: [PublishedPort] = [],
        imageJob: ImageJobStatus? = nil
    ) {
        self.state = state
        self.step = step
        self.apiEndpoint = apiEndpoint
        self.vm = vm
        self.nestedVirt = nestedVirt
        self.kvmPresent = kvmPresent
        self.lastError = lastError
        self.publishedPorts = publishedPorts
        self.imageJob = imageJob
    }
}

public enum EngineEvent: Equatable, Sendable {
    case status(EngineStatus)
    case log(source: LogSource, line: String)
    case images(NodeImageList)
}

extension EngineRequest: Codable {
    enum CodingKeys: String, CodingKey {
        case op
        case force
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
        case "start":
            self = .start
        case "stop":
            self = .stop
        case "prepareUpdate":
            self = .prepareUpdate
        case "reset":
            let force = try container.decodeIfPresent(Bool.self, forKey: .force) ?? false
            self = .reset(force: force)
        case "status":
            self = .status
        case "subscribe":
            self = .subscribe
        case "loadImage":
            let path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
            self = .loadImage(path: path)
        case "imageList":
            self = .imageList
        case "imagePrune":
            self = .imagePrune
        default:
            throw EngineErrorCode.unknownOp
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start:
            try container.encode("start", forKey: .op)
        case .stop:
            try container.encode("stop", forKey: .op)
        case .prepareUpdate:
            try container.encode("prepareUpdate", forKey: .op)
        case .reset(let force):
            try container.encode("reset", forKey: .op)
            try container.encode(force, forKey: .force)
        case .status:
            try container.encode("status", forKey: .op)
        case .subscribe:
            try container.encode("subscribe", forKey: .op)
        case .loadImage(let path):
            try container.encode("loadImage", forKey: .op)
            try container.encode(path, forKey: .path)
        case .imageList:
            try container.encode("imageList", forKey: .op)
        case .imagePrune:
            try container.encode("imagePrune", forKey: .op)
        }
    }
}

extension EngineReply: Codable {
    enum CodingKeys: String, CodingKey {
        case ok
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let code = try container.decodeIfPresent(EngineErrorCode.self, forKey: .error) {
            self = .error(code)
            return
        }
        if try container.decodeIfPresent(Bool.self, forKey: .ok) == true {
            self = .ok
            return
        }
        throw EngineErrorCode.invalidRequest
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ok:
            try container.encode(true, forKey: .ok)
        case .error(let code):
            try container.encode(code, forKey: .error)
        }
    }
}

extension EngineStatus: Codable {
    enum CodingKeys: String, CodingKey {
        case state
        case step
        case apiEndpoint
        case vm
        case nestedVirt
        case kvmPresent
        case lastError
        case publishedPorts
        case imageJob
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(ClusterState.self, forKey: .state)
        step = try container.decodeIfPresent(String.self, forKey: .step)
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint)
        vm = try container.decodeIfPresent(VMMetrics.self, forKey: .vm)
        nestedVirt = try container.decodeIfPresent(Bool.self, forKey: .nestedVirt) ?? false
        kvmPresent = try container.decodeIfPresent(Bool.self, forKey: .kvmPresent)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        publishedPorts = try container.decodeIfPresent([PublishedPort].self, forKey: .publishedPorts) ?? []
        imageJob = try container.decodeIfPresent(ImageJobStatus.self, forKey: .imageJob)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encodeNilIfAbsent(step, forKey: .step)
        try container.encodeNilIfAbsent(apiEndpoint, forKey: .apiEndpoint)
        try container.encodeNilIfAbsent(vm, forKey: .vm)
        try container.encode(nestedVirt, forKey: .nestedVirt)
        try container.encodeNilIfAbsent(kvmPresent, forKey: .kvmPresent)
        try container.encodeNilIfAbsent(lastError, forKey: .lastError)
        try container.encode(publishedPorts, forKey: .publishedPorts)
        try container.encodeNilIfAbsent(imageJob, forKey: .imageJob)
    }
}

extension EngineEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case source
        case line
        case state
        case step
        case apiEndpoint
        case vm
        case nestedVirt
        case kvmPresent
        case lastError
        case publishedPorts
        case imageJob
        case items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "status":
            self = .status(try EngineStatus(from: decoder))
        case "log":
            let source = try container.decode(LogSource.self, forKey: .source)
            let line = try container.decode(String.self, forKey: .line)
            self = .log(source: source, line: line)
        case "images":
            let items = try container.decodeIfPresent([NodeImage].self, forKey: .items) ?? []
            self = .images(NodeImageList(items: items))
        default:
            throw EngineErrorCode.invalidRequest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status(let status):
            try container.encode("status", forKey: .type)
            try status.encode(to: encoder)
        case .log(let source, let line):
            try container.encode("log", forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(line, forKey: .line)
        case .images(let list):
            try container.encode("images", forKey: .type)
            try container.encode(list.items, forKey: .items)
        }
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodeNilIfAbsent<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
