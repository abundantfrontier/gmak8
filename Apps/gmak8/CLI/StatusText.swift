import Gmak8XPC

enum StatusText {
    static func render(_ status: EngineStatus) -> String {
        var lines = ["State: \(displayName(status.state))"]
        if let endpoint = status.apiEndpoint {
            lines.append("API: \(endpoint)")
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
