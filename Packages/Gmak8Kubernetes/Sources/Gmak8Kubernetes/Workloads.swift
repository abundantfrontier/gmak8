import Foundation

public enum WorkloadKind: String, CaseIterable, Sendable, Equatable, Identifiable {
    case pod
    case deployment
    case statefulSet
    case daemonSet
    case job
    case cronJob

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pod: return WorkloadsCopy.pods
        case .deployment: return WorkloadsCopy.deployments
        case .statefulSet: return WorkloadsCopy.statefulSets
        case .daemonSet: return WorkloadsCopy.daemonSets
        case .job: return WorkloadsCopy.jobs
        case .cronJob: return WorkloadsCopy.cronJobs
        }
    }
}

public enum WorkloadNamespaceScope: Equatable, Sendable, Hashable {
    case all
    case named(String)

    public var title: String {
        switch self {
        case .all:
            return WorkloadsCopy.allNamespaces
        case .named(let name):
            return name
        }
    }
}

public struct WorkloadRow: Equatable, Hashable, Sendable, Identifiable {
    public var kind: WorkloadKind
    public var namespace: String
    public var name: String
    public var status: String
    public var ready: String
    public var createdAt: Date?

    public var id: String { "\(kind.rawValue):\(namespace)/\(name)" }

    public init(
        kind: WorkloadKind,
        namespace: String,
        name: String,
        status: String,
        ready: String,
        createdAt: Date? = nil
    ) {
        self.kind = kind
        self.namespace = namespace
        self.name = name
        self.status = status
        self.ready = ready
        self.createdAt = createdAt
    }
}

public struct PodEnvVar: Equatable, Sendable, Identifiable {
    public var name: String
    public var display: String

    public var id: String { name }

    public init(name: String, display: String) {
        self.name = name
        self.display = display
    }
}

public struct PodContainerInfo: Equatable, Sendable, Identifiable {
    public var name: String
    public var image: String
    public var ready: Bool
    public var restarts: Int
    public var env: [PodEnvVar]

    public var id: String { name }

    public init(name: String, image: String, ready: Bool, restarts: Int, env: [PodEnvVar] = []) {
        self.name = name
        self.image = image
        self.ready = ready
        self.restarts = restarts
        self.env = env
    }
}

public struct PodEvent: Equatable, Sendable, Identifiable {
    public var type: String
    public var reason: String
    public var message: String
    public var count: Int
    public var lastSeen: Date?

    public var id: String { "\(type):\(reason):\(message):\(count)" }

    public init(type: String, reason: String, message: String, count: Int, lastSeen: Date? = nil) {
        self.type = type
        self.reason = reason
        self.message = message
        self.count = count
        self.lastSeen = lastSeen
    }
}

public struct PodDetail: Equatable, Sendable {
    public var namespace: String
    public var name: String
    public var phase: String
    public var ready: Bool
    public var nodeName: String?
    public var containers: [PodContainerInfo]
    public var yaml: String
    public var events: [PodEvent]

    public init(
        namespace: String,
        name: String,
        phase: String,
        ready: Bool,
        nodeName: String? = nil,
        containers: [PodContainerInfo] = [],
        yaml: String = "",
        events: [PodEvent] = []
    ) {
        self.namespace = namespace
        self.name = name
        self.phase = phase
        self.ready = ready
        self.nodeName = nodeName
        self.containers = containers
        self.yaml = yaml
        self.events = events
    }
}

public enum WorkloadsCopy {
    public static let pods = "Pods"
    public static let deployments = "Deployments"
    public static let statefulSets = "StatefulSets"
    public static let daemonSets = "DaemonSets"
    public static let jobs = "Jobs"
    public static let cronJobs = "CronJobs"
    public static let allNamespaces = "All namespaces"
    public static let empty = "Apply a manifest, or gmak8 build an image and deploy."
    public static let filter = "Filter"
    public static let status = "Status"
    public static let logs = "Logs"
    public static let events = "Events"
    public static let yaml = "YAML"
    public static let containers = "Containers"
    public static let portForward = "Port-forward"
    public static let openShell = "Open shell in Terminal"
    public static let localPort = "Local port"
    public static let remotePort = "Remote port"
    public static let bindLoopback = "Binds 127.0.0.1 only."
    public static let secretValue = "••••"
    public static let noEvents = "No events."
    public static let namespace = "Namespace"
    public static let kind = "Kind"
}

public enum PodLogCap {
    public static let maxLines = 10_000

    public static func clipped(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines {
            return text
        }
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}

public enum WorkloadAge {
    public static func format(from createdAt: Date?, now: Date = Date()) -> String {
        guard let createdAt else {
            return "—"
        }
        let seconds = max(0, Int(now.timeIntervalSince(createdAt)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86_400 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 86_400)d"
    }
}

public protocol WorkloadsClient: Sendable {
    func namespaces() async throws -> [String]
    func list(kind: WorkloadKind, scope: WorkloadNamespaceScope) async throws -> [WorkloadRow]
    func pod(namespace: String, name: String) async throws -> PodDetail
    func podLogs(namespace: String, name: String, container: String?, tailLines: Int) async throws -> String
}

public struct FakeWorkloadsClient: WorkloadsClient {
    public var namespacesList: [String]
    public var rows: [WorkloadRow]
    public var pods: [String: PodDetail]
    public var logs: [String: String]
    public var error: ClusterOverviewError?

    public init(
        namespacesList: [String] = ["default", "kube-system"],
        rows: [WorkloadRow] = FakeWorkloadsClient.sampleRows,
        pods: [String: PodDetail] = [:],
        logs: [String: String] = [:],
        error: ClusterOverviewError? = nil
    ) {
        self.namespacesList = namespacesList
        self.rows = rows
        self.pods = pods
        self.logs = logs
        self.error = error
    }

    public static let sampleRows: [WorkloadRow] = [
        WorkloadRow(
            kind: .pod,
            namespace: "kube-system",
            name: "coredns",
            status: "Running",
            ready: "1/1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    ]

    public func namespaces() async throws -> [String] {
        if let error { throw error }
        return namespacesList
    }

    public func list(kind: WorkloadKind, scope: WorkloadNamespaceScope) async throws -> [WorkloadRow] {
        if let error { throw error }
        return rows.filter { row in
            guard row.kind == kind else { return false }
            switch scope {
            case .all:
                return true
            case .named(let name):
                return row.namespace == name
            }
        }
    }

    public func pod(namespace: String, name: String) async throws -> PodDetail {
        if let error { throw error }
        let key = "\(namespace)/\(name)"
        if let pods = pods[key] {
            return pods
        }
        return PodDetail(namespace: namespace, name: name, phase: "Running", ready: true)
    }

    public func podLogs(namespace: String, name: String, container: String?, tailLines: Int) async throws
        -> String
    {
        if let error { throw error }
        let key = "\(namespace)/\(name)"
        let raw = logs[key] ?? ""
        let clipped = PodLogCap.clipped(raw)
        let lines = clipped.split(separator: "\n", omittingEmptySubsequences: false)
        if tailLines > 0, lines.count > tailLines {
            return lines.suffix(tailLines).joined(separator: "\n")
        }
        return clipped
    }
}
