import Foundation
import Gmak8Kit
import zlib

public struct DiagnosticsArchiveRequest: Equatable, Sendable {
    public var settingsJSON: String
    public var engineLog: String
    public var serialLog: String
    public var kubectlNodes: String?
    public var kubectlPods: String?
    public var versions: String
    public var kubeconfig: String?
    public var includeCredentials: Bool

    public init(
        settingsJSON: String,
        engineLog: String,
        serialLog: String,
        kubectlNodes: String? = nil,
        kubectlPods: String? = nil,
        versions: String,
        kubeconfig: String? = nil,
        includeCredentials: Bool = false
    ) {
        self.settingsJSON = settingsJSON
        self.engineLog = engineLog
        self.serialLog = serialLog
        self.kubectlNodes = kubectlNodes
        self.kubectlPods = kubectlPods
        self.versions = versions
        self.kubeconfig = kubeconfig
        self.includeCredentials = includeCredentials
    }
}

public enum SecretRedactor {
    public static let placeholder = "••••"

    public static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)("(?:password|token|secret|client[-_]?secret)"\s*:\s*")[^"]*"#,
            #"(?i)((?:password|token|secret|client-key-data|client-certificate-data|client[-_]?secret)\s*[:=]\s*)\S+"#,
            #"(?i)(bearer\s+)\S+"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1\(placeholder)"
            )
        }
        return result
    }
}

public enum DiagnosticsArchive {
    public static func files(from request: DiagnosticsArchiveRequest) -> [String: Data] {
        var result: [String: String] = [:]
        result["settings.json"] = SecretRedactor.redact(request.settingsJSON)
        result["engine.log"] = SecretRedactor.redact(request.engineLog)
        if !request.serialLog.isEmpty {
            result["serial.log"] = SecretRedactor.redact(request.serialLog)
        }
        result["versions.txt"] = request.versions
        if let nodes = request.kubectlNodes, !nodes.isEmpty {
            result["kubectl-nodes.txt"] = SecretRedactor.redact(nodes)
        }
        if let pods = request.kubectlPods, !pods.isEmpty {
            result["kubectl-pods.txt"] = SecretRedactor.redact(pods)
        }
        if request.includeCredentials, let kubeconfig = request.kubeconfig, !kubeconfig.isEmpty {
            result["kubeconfig"] = kubeconfig
        }
        return result.mapValues { Data($0.utf8) }
    }

    public static let kubectlExecutable = "/usr/bin/env"

    public static func kubectlArguments(resource: String, kubeconfig: String) -> [String] {
        ["kubectl", "--kubeconfig", kubeconfig, "get", resource, "-A"]
    }

    public static func collect(
        paths: HostPaths,
        status: EngineStatus,
        includeCredentials: Bool,
        fileManager: FileManager = .default,
        runKubectl: ((String, [String]) throws -> String)? = nil
    ) -> DiagnosticsArchiveRequest {
        func read(_ url: URL) -> String {
            let path = url.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path) else {
                return ""
            }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        var engine = "state=\(status.state.rawValue)\n"
        if let step = status.step {
            engine += "step=\(step)\n"
        }
        if let lastError = status.lastError {
            engine += "lastError=\(lastError)\n"
        }
        if let api = status.apiEndpoint {
            engine += "apiEndpoint=\(api)\n"
        }
        let gvproxy = read(paths.gvproxyLog)
        if !gvproxy.isEmpty {
            engine += "\n--- gvproxy.log ---\n" + gvproxy
        }
        let kubeconfigPath = paths.kubeconfigFile.path(percentEncoded: false)
        var kubectlNodes: String?
        var kubectlPods: String?
        if fileManager.fileExists(atPath: kubeconfigPath) {
            let runner = runKubectl ?? runKubectlProcess
            kubectlNodes = captureKubectl(
                resource: "nodes",
                kubeconfig: kubeconfigPath,
                run: runner
            )
            kubectlPods = captureKubectl(
                resource: "pods",
                kubeconfig: kubeconfigPath,
                run: runner
            )
        }
        let kubeconfig: String?
        if includeCredentials {
            let text = read(paths.kubeconfigFile)
            kubeconfig = text.isEmpty ? nil : text
        } else {
            kubeconfig = nil
        }
        return DiagnosticsArchiveRequest(
            settingsJSON: read(paths.settingsFile),
            engineLog: engine,
            serialLog: read(paths.serialLog),
            kubectlNodes: kubectlNodes,
            kubectlPods: kubectlPods,
            versions: "gmak8 \(Gmak8Kit.version)\nk3s \(K3sPin.version)\n",
            kubeconfig: kubeconfig,
            includeCredentials: includeCredentials
        )
    }

    public static func writeZip(
        files: [String: Data],
        to url: URL,
        fileManager: FileManager = .default,
        ownerReadWrite: Bool = false
    ) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StoredZip.data(files: files).write(to: url, options: .atomic)
        if ownerReadWrite {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
    }

    private static func captureKubectl(
        resource: String,
        kubeconfig: String,
        run: (String, [String]) throws -> String
    ) -> String {
        let arguments = kubectlArguments(resource: resource, kubeconfig: kubeconfig)
        do {
            return try run(kubectlExecutable, arguments)
        } catch {
            return "kubectl get \(resource) -A failed: \(error.localizedDescription)"
        }
    }

    static func runKubectlProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return out
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let detail = err.isEmpty ? out : err
        throw ClusterBringUpError(
            message: "exit \(process.terminationStatus)\(detail.isEmpty ? "" : ": \(detail)")"
        )
    }
}

private enum StoredZip {
    static func data(files: [String: Data]) -> Data {
        var local = Data()
        var central = Data()
        for name in files.keys.sorted() {
            let payload = files[name] ?? Data()
            let nameData = Data(name.utf8)
            let headerOffset = UInt32(local.count)
            let crc = crc32(payload)
            let size = UInt32(payload.count)
            let nameLength = UInt16(nameData.count)
            appendLocalHeader(
                to: &local,
                crc: crc,
                size: size,
                nameLength: nameLength,
                name: nameData,
                payload: payload
            )
            appendCentralHeader(
                to: &central,
                crc: crc,
                size: size,
                nameLength: nameLength,
                name: nameData,
                localOffset: headerOffset
            )
        }
        let cdOffset = UInt32(local.count)
        let cdSize = UInt32(central.count)
        var output = local
        output.append(central)
        appendEOCD(to: &output, count: UInt16(files.count), cdSize: cdSize, cdOffset: cdOffset)
        return output
    }

    private static func appendLocalHeader(
        to data: inout Data,
        crc: UInt32,
        size: UInt32,
        nameLength: UInt16,
        name: Data,
        payload: Data
    ) {
        data.append(le32(0x0403_4b50))
        data.append(le16(20))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le32(crc))
        data.append(le32(size))
        data.append(le32(size))
        data.append(le16(nameLength))
        data.append(le16(0))
        data.append(name)
        data.append(payload)
    }

    private static func appendCentralHeader(
        to data: inout Data,
        crc: UInt32,
        size: UInt32,
        nameLength: UInt16,
        name: Data,
        localOffset: UInt32
    ) {
        data.append(le32(0x0201_4b50))
        data.append(le16(20))
        data.append(le16(20))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le32(crc))
        data.append(le32(size))
        data.append(le32(size))
        data.append(le16(nameLength))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le32(0))
        data.append(le32(localOffset))
        data.append(name)
    }

    private static func appendEOCD(to data: inout Data, count: UInt16, cdSize: UInt32, cdOffset: UInt32) {
        data.append(le32(0x0605_4b50))
        data.append(le16(0))
        data.append(le16(0))
        data.append(le16(count))
        data.append(le16(count))
        data.append(le32(cdSize))
        data.append(le32(cdOffset))
        data.append(le16(0))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            return UInt32(zlib.crc32(0, buffer.baseAddress, uInt(buffer.count)))
        }
    }

    private static func le16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 2)
    }

    private static func le32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 4)
    }
}
