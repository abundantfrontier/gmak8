import Foundation

public struct HostPortOccupant: Equatable, Sendable {
    public var pid: Int
    public var command: String
    public var port: Int

    public init(pid: Int, command: String, port: Int) {
        self.pid = pid
        self.command = command
        self.port = port
    }
}

public enum HostPortLsofError: Error, Equatable, LocalizedError, Sendable {
    case failed(status: Int32)

    public var errorDescription: String? {
        switch self {
        case .failed(let status):
            return "lsof exited \(status)"
        }
    }
}

public enum HostPortLsof {
    public static let executable = "/usr/sbin/lsof"

    public static func arguments(port: Int) -> [String] {
        ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
    }

    public static func probePorts(kind: RecoveryKind, collidingNodePorts: [Int]) -> [Int] {
        switch kind {
        case .apiPortConflict:
            return [RecoveryPorts.api, RecoveryPorts.apiFallback]
        case .ingressPortConflict:
            return [
                RecoveryPorts.http, RecoveryPorts.httpFallback, RecoveryPorts.https, RecoveryPorts.httpsFallback,
            ]
        case .nodePortCollision:
            return collidingNodePorts
        default:
            return []
        }
    }

    public static func parse(_ output: String, port: Int) -> [HostPortOccupant] {
        var occupants: [HostPortOccupant] = []
        var seen = Set<Int>()
        for line in output.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 2 else {
                continue
            }
            if tokens[0].caseInsensitiveCompare("COMMAND") == .orderedSame {
                continue
            }
            guard let pid = Int(tokens[1]), pid > 0, seen.insert(pid).inserted else {
                continue
            }
            occupants.append(HostPortOccupant(pid: pid, command: tokens[0], port: port))
        }
        return occupants
    }

    public static func occupancyLine(port: Int, occupants: [HostPortOccupant]) -> String {
        if occupants.isEmpty {
            return "\(port) is free"
        }
        let parts = occupants.map { occupant in
            "pid \(occupant.pid) (\(occupant.command))"
        }
        return "\(port) in use by \(parts.joined(separator: ", "))"
    }

    public static func occupancyLines(
        ports: [Int],
        run: (String, [String]) throws -> String
    ) -> [String] {
        ports.map { port in
            do {
                let occupants = try occupants(port: port, run: run)
                return occupancyLine(port: port, occupants: occupants)
            } catch {
                return "\(port) lsof failed: \(error.localizedDescription)"
            }
        }
    }

    public static func occupancyLines(ports: [Int]) -> [String] {
        occupancyLines(ports: ports, run: runProcess)
    }

    public static func occupants(
        port: Int,
        run: (String, [String]) throws -> String
    ) throws -> [HostPortOccupant] {
        let output = try run(executable, arguments(port: port))
        return parse(output, port: port)
    }

    public static func occupants(port: Int) throws -> [HostPortOccupant] {
        try occupants(port: port, run: runProcess)
    }

    static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        // lsof exits 1 when nothing matched; 2+ is a real failure.
        if process.terminationStatus >= 2 {
            throw HostPortLsofError.failed(status: process.terminationStatus)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
