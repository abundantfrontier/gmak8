import Gmak8XPC

enum StatusText {
    static func render(_ status: EngineStatus) -> String {
        var lines = ["State: \(displayName(status.state))"]
        if let endpoint = status.apiEndpoint {
            lines.append("API: \(endpoint)")
        }
        for port in status.publishedPorts {
            var line = "Port: \(port.hostURL) \(port.service)"
            if port.collision != .published {
                line += " \(port.collision.rawValue)"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func displayName(_ state: ClusterState) -> String {
        switch state {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .degraded: "Degraded"
        case .paused: "Paused"
        case .stopping: "Stopping"
        case .failed: "Failed"
        }
    }
}
