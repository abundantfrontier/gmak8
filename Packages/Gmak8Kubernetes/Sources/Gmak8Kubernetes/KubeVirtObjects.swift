import Foundation

public enum KubeVirtKind: String, CaseIterable, Sendable, Equatable, Identifiable {
    case virtualMachine
    case virtualMachineInstance
    case virtualMachinePool
    case dataVolume

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .virtualMachine: return KubeVirtCopy.virtualMachines
        case .virtualMachineInstance: return KubeVirtCopy.vmis
        case .virtualMachinePool: return KubeVirtCopy.vmPools
        case .dataVolume: return KubeVirtCopy.dataVolumes
        }
    }

    public var apiGroup: String {
        switch self {
        case .virtualMachine, .virtualMachineInstance:
            return "kubevirt.io"
        case .virtualMachinePool:
            return "pool.kubevirt.io"
        case .dataVolume:
            return "cdi.kubevirt.io"
        }
    }

    public var apiVersion: String {
        switch self {
        case .virtualMachine, .virtualMachineInstance:
            return "v1"
        case .virtualMachinePool:
            return "v1alpha1"
        case .dataVolume:
            return "v1beta1"
        }
    }

    public var plural: String {
        switch self {
        case .virtualMachine: return "virtualmachines"
        case .virtualMachineInstance: return "virtualmachineinstances"
        case .virtualMachinePool: return "virtualmachinepools"
        case .dataVolume: return "datavolumes"
        }
    }

    public var resourceKind: String {
        switch self {
        case .virtualMachine: return "VirtualMachine"
        case .virtualMachineInstance: return "VirtualMachineInstance"
        case .virtualMachinePool: return "VirtualMachinePool"
        case .dataVolume: return "DataVolume"
        }
    }
}

public struct KubeVirtRow: Equatable, Hashable, Sendable, Identifiable {
    public var kind: KubeVirtKind
    public var namespace: String
    public var name: String
    public var status: String
    public var ready: String
    public var createdAt: Date?

    public var id: String { "\(kind.rawValue):\(namespace)/\(name)" }

    public init(
        kind: KubeVirtKind,
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

public struct KubeVirtCondition: Equatable, Sendable, Identifiable {
    public var type: String
    public var status: String
    public var reason: String
    public var message: String

    public var id: String { "\(type):\(reason):\(message)" }

    public init(type: String, status: String, reason: String = "", message: String = "") {
        self.type = type
        self.status = status
        self.reason = reason
        self.message = message
    }
}

public struct KubeVirtDetail: Equatable, Sendable {
    public var kind: KubeVirtKind
    public var namespace: String
    public var name: String
    public var phase: String
    public var ready: Bool
    public var running: Bool?
    public var instancetype: String?
    public var dataVolumes: [String]
    public var conditions: [KubeVirtCondition]
    public var events: [PodEvent]
    public var yaml: String
    public var pendingUnschedulable: Bool

    public init(
        kind: KubeVirtKind,
        namespace: String,
        name: String,
        phase: String,
        ready: Bool,
        running: Bool? = nil,
        instancetype: String? = nil,
        dataVolumes: [String] = [],
        conditions: [KubeVirtCondition] = [],
        events: [PodEvent] = [],
        yaml: String = "",
        pendingUnschedulable: Bool = false
    ) {
        self.kind = kind
        self.namespace = namespace
        self.name = name
        self.phase = phase
        self.ready = ready
        self.running = running
        self.instancetype = instancetype
        self.dataVolumes = dataVolumes
        self.conditions = conditions
        self.events = events
        self.yaml = yaml
        self.pendingUnschedulable = pendingUnschedulable
    }
}

public enum KubeVirtCopy {
    public static let virtualMachines = "VirtualMachines"
    public static let vmis = "VMIs"
    public static let vmPools = "VMPools"
    public static let dataVolumes = "DataVolumes"
    public static let empty = "Apply a VirtualMachine, VMI, VMPool, or DataVolume."
    public static let nestedVirtUnsupported =
        "KubeVirt is installed. This Mac cannot run nested VMs (needs Apple Silicon M3 or later and macOS 15+). API objects can still be created; VMIs will stay Pending."
    public static let start = "Start"
    public static let stop = "Stop"
    public static let running = "Running"
    public static let instancetype = "Instancetype"
    public static let conditions = "Conditions"
    public static let noConditions = "No conditions."
    public static let diagnostics = "Diagnostics"
    public static let kind = "Kind"
}

public enum KubeVirtFields {
    public static func row(
        kind: KubeVirtKind,
        namespace: String,
        name: String,
        spec: [String: Any],
        status: [String: Any],
        createdAt: Date? = nil
    ) -> KubeVirtRow {
        KubeVirtRow(
            kind: kind,
            namespace: namespace,
            name: name,
            status: phase(kind: kind, spec: spec, status: status),
            ready: readyText(kind: kind, spec: spec, status: status),
            createdAt: createdAt
        )
    }

    public static func detail(
        kind: KubeVirtKind,
        namespace: String,
        name: String,
        spec: [String: Any],
        status: [String: Any],
        events: [PodEvent] = [],
        yaml: String = ""
    ) -> KubeVirtDetail {
        let phaseText = phase(kind: kind, spec: spec, status: status)
        let conditions = conditions(status)
        return KubeVirtDetail(
            kind: kind,
            namespace: namespace,
            name: name,
            phase: phaseText,
            ready: isReady(kind: kind, spec: spec, status: status),
            running: kind == .virtualMachine ? isRunning(spec) : nil,
            instancetype: instancetypeName(spec),
            dataVolumes: dataVolumeNames(kind: kind, name: name, spec: spec),
            conditions: conditions,
            events: events,
            yaml: yaml,
            pendingUnschedulable: isPendingUnschedulable(phase: phaseText, conditions: conditions)
        )
    }

    public static func phase(kind: KubeVirtKind, spec: [String: Any], status: [String: Any]) -> String {
        switch kind {
        case .virtualMachine:
            if let printable = string(status["printableStatus"]), !printable.isEmpty {
                return printable
            }
            return isRunning(spec) ? "Running" : "Stopped"
        case .virtualMachineInstance, .dataVolume:
            return string(status["phase"]) ?? "Unknown"
        case .virtualMachinePool:
            if let printable = string(status["printableStatus"]), !printable.isEmpty {
                return printable
            }
            if let phase = string(status["phase"]), !phase.isEmpty {
                return phase
            }
            let ready = intValue(status["readyReplicas"]) ?? 0
            let total = intValue(spec["replicas"]) ?? intValue(status["replicas"]) ?? 0
            return total == 0 ? "Stopped" : (ready >= total ? "Ready" : "Not ready")
        }
    }

    public static func readyText(kind: KubeVirtKind, spec: [String: Any], status: [String: Any]) -> String {
        if kind == .virtualMachinePool {
            let ready = intValue(status["readyReplicas"]) ?? 0
            let total = intValue(spec["replicas"]) ?? intValue(status["replicas"]) ?? 0
            return "\(ready)/\(total)"
        }
        return isReady(kind: kind, spec: spec, status: status) ? "True" : "False"
    }

    public static func isReady(kind: KubeVirtKind, spec: [String: Any], status: [String: Any]) -> Bool {
        if let ready = boolValue(status["ready"]) {
            return ready
        }
        if condition(status, type: "Ready")?.status == "True" {
            return true
        }
        switch kind {
        case .virtualMachine:
            return phase(kind: kind, spec: spec, status: status) == "Running"
        case .virtualMachineInstance:
            return string(status["phase"]) == "Running"
        case .virtualMachinePool:
            let ready = intValue(status["readyReplicas"]) ?? 0
            let total = intValue(spec["replicas"]) ?? 0
            return total > 0 && ready >= total
        case .dataVolume:
            return string(status["phase"]) == "Succeeded"
        }
    }

    public static func isRunning(_ spec: [String: Any]) -> Bool {
        if let strategy = string(spec["runStrategy"]) {
            return strategy != "Halted"
        }
        return boolValue(spec["running"]) ?? false
    }

    public static func withRunning(_ spec: [String: Any], running: Bool) -> [String: Any] {
        var copy = spec
        if spec["runStrategy"] != nil {
            copy["runStrategy"] = running ? "Always" : "Halted"
            copy.removeValue(forKey: "running")
        } else {
            copy["running"] = running
        }
        return copy
    }

    public static func instancetypeName(_ spec: [String: Any]) -> String? {
        guard let instancetype = dictionary(spec["instancetype"]),
            let name = string(instancetype["name"]), !name.isEmpty
        else {
            return nil
        }
        if let kind = string(instancetype["kind"]), !kind.isEmpty {
            return "\(kind)/\(name)"
        }
        return name
    }

    public static func dataVolumeNames(kind: KubeVirtKind, name: String, spec: [String: Any]) -> [String] {
        if kind == .dataVolume {
            return [name]
        }
        var names: [String] = []
        if let templates = spec["dataVolumeTemplates"] as? [Any] {
            for item in templates {
                if let meta = dictionary(dictionary(item)?["metadata"]), let dv = string(meta["name"]) {
                    names.append(dv)
                }
            }
        }
        let volumes = dictionary(dictionary(spec["template"])?["spec"])?["volumes"] as? [Any] ?? []
        for volume in volumes {
            if let dv = dictionary(dictionary(volume)?["dataVolume"]), let dvName = string(dv["name"]) {
                names.append(dvName)
            }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    public static func conditions(_ status: [String: Any]) -> [KubeVirtCondition] {
        guard let items = status["conditions"] as? [Any] else {
            return []
        }
        return items.compactMap { item in
            guard let dict = dictionary(item) else {
                return nil
            }
            return KubeVirtCondition(
                type: string(dict["type"]) ?? "",
                status: string(dict["status"]) ?? "",
                reason: string(dict["reason"]) ?? "",
                message: string(dict["message"]) ?? ""
            )
        }
    }

    public static func isPendingUnschedulable(phase: String, conditions: [KubeVirtCondition]) -> Bool {
        let pending = phase.caseInsensitiveCompare("Pending") == .orderedSame
        guard pending else {
            return false
        }
        return conditions.contains { condition in
            let haystack = "\(condition.type) \(condition.reason) \(condition.message)".lowercased()
            return haystack.contains("unschedulable") || haystack.contains("/dev/kvm")
                || haystack.contains("virtlauncher")
        }
    }

    public static func dictionary(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            return dict
        }
        if let dict = value as? [String: any Sendable] {
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[key] = nested
            }
            return out
        }
        if let dict = value as? NSDictionary {
            return dict as? [String: Any]
        }
        return nil
    }

    public static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        return nil
    }

    public static func boolValue(_ value: Any?) -> Bool? {
        if let flag = value as? Bool {
            return flag
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return nil
    }

    public static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func condition(_ status: [String: Any], type: String) -> KubeVirtCondition? {
        conditions(status).first { $0.type == type }
    }
}

public protocol KubeVirtClient: Sendable {
    func namespaces() async throws -> [String]
    func list(kind: KubeVirtKind, scope: WorkloadNamespaceScope) async throws -> [KubeVirtRow]
    func detail(kind: KubeVirtKind, namespace: String, name: String) async throws -> KubeVirtDetail
    func setRunning(namespace: String, name: String, running: Bool) async throws -> KubeVirtDetail
}

public struct FakeKubeVirtClient: KubeVirtClient {
    public var namespacesList: [String]
    public var rows: [KubeVirtRow]
    public var details: [String: KubeVirtDetail]
    public var error: ClusterOverviewError?

    public init(
        namespacesList: [String] = ["default"],
        rows: [KubeVirtRow] = FakeKubeVirtClient.sampleRows,
        details: [String: KubeVirtDetail] = FakeKubeVirtClient.sampleDetails,
        error: ClusterOverviewError? = nil
    ) {
        self.namespacesList = namespacesList
        self.rows = rows
        self.details = details
        self.error = error
    }

    public static let sampleRows: [KubeVirtRow] = [
        KubeVirtRow(
            kind: .virtualMachine,
            namespace: "default",
            name: "cirros",
            status: "Running",
            ready: "True",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        KubeVirtRow(
            kind: .virtualMachineInstance,
            namespace: "default",
            name: "cirros",
            status: "Pending",
            ready: "False",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        KubeVirtRow(
            kind: .virtualMachinePool,
            namespace: "default",
            name: "workers",
            status: "Ready",
            ready: "1/1"
        ),
        KubeVirtRow(
            kind: .dataVolume,
            namespace: "default",
            name: "cirros-dv",
            status: "Succeeded",
            ready: "True"
        ),
    ]

    public static let sampleDetails: [String: KubeVirtDetail] = [
        "virtualMachine:default/cirros": KubeVirtDetail(
            kind: .virtualMachine,
            namespace: "default",
            name: "cirros",
            phase: "Running",
            ready: true,
            running: true,
            instancetype: "VirtualMachineClusterInstancetype/u1.nano",
            dataVolumes: ["cirros-dv"]
        ),
        "virtualMachineInstance:default/cirros": KubeVirtDetail(
            kind: .virtualMachineInstance,
            namespace: "default",
            name: "cirros",
            phase: "Pending",
            ready: false,
            conditions: [
                KubeVirtCondition(
                    type: "Ready",
                    status: "False",
                    reason: "VirtLauncher.Unschedulable",
                    message: "0/1 nodes are available: 1 Insufficient kvm, missing /dev/kvm."
                )
            ],
            pendingUnschedulable: true
        ),
    ]

    public func namespaces() async throws -> [String] {
        if let error { throw error }
        return namespacesList
    }

    public func list(kind: KubeVirtKind, scope: WorkloadNamespaceScope) async throws -> [KubeVirtRow] {
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

    public func detail(kind: KubeVirtKind, namespace: String, name: String) async throws -> KubeVirtDetail {
        if let error { throw error }
        let key = "\(kind.rawValue):\(namespace)/\(name)"
        if let details = details[key] {
            return details
        }
        return KubeVirtDetail(kind: kind, namespace: namespace, name: name, phase: "Unknown", ready: false)
    }

    public func setRunning(namespace: String, name: String, running: Bool) async throws -> KubeVirtDetail {
        if let error { throw error }
        let key = "virtualMachine:\(namespace)/\(name)"
        var detail =
            details[key]
            ?? KubeVirtDetail(
                kind: .virtualMachine,
                namespace: namespace,
                name: name,
                phase: running ? "Running" : "Stopped",
                ready: running
            )
        detail.running = running
        detail.phase = running ? "Running" : "Stopped"
        return detail
    }
}
