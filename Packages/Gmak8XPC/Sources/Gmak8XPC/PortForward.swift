import Foundation

public enum L1SSHBridge {
    public static let hostPort = 22_022
    public static let guestPort = 22
    public static let service = "sshd"
}

public enum PortForwardKind: String, Codable, Equatable, Sendable {
    case pod
    case vm
    case vmi
}

public struct PortForwardSession: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var kind: PortForwardKind
    public var namespace: String
    public var name: String
    public var local: Int
    public var remote: Int
    public var address: String

    public init(
        id: String,
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int,
        address: String = VirtctlPortForward.loopback
    ) {
        self.id = id
        self.kind = kind
        self.namespace = namespace
        self.name = name
        self.local = local
        self.remote = remote
        self.address = address
    }
}

public enum PortForwardError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedKind(PortForwardKind)
    case forbiddenHostPort(Int)
    case invalidPort
    case invalidTarget(String)
    case virtctlMissing
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .unsupportedKind(.pod):
            return "Pod port-forward uses the pod detail in the app (Terminal). Engine forwards are vm or vmi."
        case .unsupportedKind(let kind):
            return "Unsupported port-forward kind \(kind.rawValue)."
        case .forbiddenHostPort(let port):
            return "Refuse host port \(port). Bind 127.0.0.1 on a high port, never 22/80/443."
        case .invalidPort:
            return "Port must be 1...65535."
        case .invalidTarget(let raw):
            return "Port-forward target must be vm/<name> or vmi/<name> (got \(raw))."
        case .virtctlMissing:
            return "virtctl is missing from Contents/Helpers."
        case .notRunning:
            return "Cluster is not running."
        }
    }
}

public enum VirtctlPortForward {
    public static let loopback = "127.0.0.1"
    public static let forbiddenHostPorts: Set<Int> = [22, 80, 443]
    public static let guestSSHPort = 22
    public static let helperName = "virtctl"
    public static let environmentOverrideKey = "GMAK8_VIRTCTL"

    public static func arguments(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int
    ) throws -> [String] {
        guard kind == .vm || kind == .vmi else {
            throw PortForwardError.unsupportedKind(kind)
        }
        guard !name.isEmpty, !name.contains("/") else {
            throw PortForwardError.invalidTarget("\(kind.rawValue)/\(name)")
        }
        try validate(local: local, remote: remote)
        let args = [
            "port-forward",
            "--address", loopback,
            "-n", namespace,
            "\(kind.rawValue)/\(name)",
            "\(local):\(remote)",
        ]
        if args.contains(where: { $0.contains("0.0.0.0") }) {
            throw PortForwardError.forbiddenHostPort(0)
        }
        return args
    }

    public static func validate(local: Int, remote: Int) throws {
        guard (1...65_535).contains(local), (1...65_535).contains(remote) else {
            throw PortForwardError.invalidPort
        }
        if forbiddenHostPorts.contains(local) {
            throw PortForwardError.forbiddenHostPort(local)
        }
    }

    public static func parseTarget(_ raw: String) throws -> (PortForwardKind, String) {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let kind = PortForwardKind(rawValue: parts[0].lowercased()),
            kind == .vm || kind == .vmi
        else {
            throw PortForwardError.invalidTarget(raw)
        }
        let name = parts[1]
        guard !name.isEmpty, !name.contains("/") else {
            throw PortForwardError.invalidTarget(raw)
        }
        return (kind, name)
    }

    public static func parsePorts(_ raw: String) throws -> (local: Int, remote: Int) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 {
            guard let remote = Int(parts[0]) else {
                throw PortForwardError.invalidPort
            }
            let local = remote == guestSSHPort ? 2222 : remote
            try validate(local: local, remote: remote)
            return (local, remote)
        }
        guard parts.count == 2, let local = Int(parts[0]), let remote = Int(parts[1]) else {
            throw PortForwardError.invalidPort
        }
        try validate(local: local, remote: remote)
        return (local, remote)
    }

    public static func bundledHelperURL(from bundleOrExecutable: URL) -> URL {
        if bundleOrExecutable.pathExtension == "app" {
            return
                bundleOrExecutable
                .appending(path: "Contents", directoryHint: .isDirectory)
                .appending(path: "Helpers", directoryHint: .isDirectory)
                .appending(path: helperName)
        }
        let parent = bundleOrExecutable.deletingLastPathComponent()
        if parent.lastPathComponent == "MacOS" {
            return
                parent
                .deletingLastPathComponent()
                .appending(path: "Helpers", directoryHint: .isDirectory)
                .appending(path: helperName)
        }
        return
            parent
            .appending(path: "Helpers", directoryHint: .isDirectory)
            .appending(path: helperName)
    }

    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        executableURL: URL = Bundle.main.bundleURL
    ) -> URL? {
        if let override = environment[environmentOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        let bundled = bundledHelperURL(from: executableURL)
        guard fileManager.isExecutableFile(atPath: bundled.path(percentEncoded: false)) else {
            return nil
        }
        return bundled
    }
}

public protocol PortForwardRuntime: Sendable {
    func start(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int
    ) throws -> PortForwardSession
    func stop(id: String) throws
    func stopAll()
}

public struct NoOpPortForwardRuntime: PortForwardRuntime {
    public init() {}

    public func start(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int
    ) throws -> PortForwardSession {
        _ = try VirtctlPortForward.arguments(
            kind: kind, namespace: namespace, name: name, local: local, remote: remote)
        throw PortForwardError.virtctlMissing
    }

    public func stop(id: String) throws {}

    public func stopAll() {}
}

/// Records argv for tests. Does not spawn virtctl.
public final class RecordingPortForwardRuntime: PortForwardRuntime, @unchecked Sendable {
    public var sessions: [PortForwardSession] = []
    public var argumentLog: [[String]] = []
    public var stopAllCount = 0
    private var nextID = 1

    public init() {}

    public func start(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int
    ) throws -> PortForwardSession {
        let args = try VirtctlPortForward.arguments(
            kind: kind, namespace: namespace, name: name, local: local, remote: remote)
        argumentLog.append(args)
        let session = PortForwardSession(
            id: "pf-\(nextID)",
            kind: kind,
            namespace: namespace,
            name: name,
            local: local,
            remote: remote
        )
        nextID += 1
        sessions.append(session)
        return session
    }

    public func stop(id: String) throws {
        sessions.removeAll { $0.id == id }
    }

    public func stopAll() {
        stopAllCount += 1
        sessions.removeAll()
    }
}

public final class ProcessPortForwardRuntime: PortForwardRuntime, @unchecked Sendable {
    private let virtctl: URL?
    private let kubeconfig: URL
    private let lock = NSLock()
    private var processes: [String: Process] = [:]

    public init(virtctl: URL?, kubeconfig: URL) {
        self.virtctl = virtctl
        self.kubeconfig = kubeconfig
    }

    public func start(
        kind: PortForwardKind,
        namespace: String,
        name: String,
        local: Int,
        remote: Int
    ) throws -> PortForwardSession {
        guard let virtctl else {
            throw PortForwardError.virtctlMissing
        }
        let args = try VirtctlPortForward.arguments(
            kind: kind, namespace: namespace, name: name, local: local, remote: remote)
        let process = Process()
        process.executableURL = virtctl
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["KUBECONFIG"] = kubeconfig.path(percentEncoded: false)
        process.environment = env
        try process.run()
        let id = "pf-\(UUID().uuidString.prefix(8).lowercased())"
        lock.lock()
        processes[id] = process
        lock.unlock()
        return PortForwardSession(
            id: id, kind: kind, namespace: namespace, name: name, local: local, remote: remote)
    }

    public func stop(id: String) throws {
        lock.lock()
        let process = processes.removeValue(forKey: id)
        lock.unlock()
        process?.terminate()
    }

    public func stopAll() {
        lock.lock()
        let all = processes
        processes.removeAll()
        lock.unlock()
        for process in all.values {
            process.terminate()
        }
    }
}
