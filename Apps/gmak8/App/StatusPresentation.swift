import Gmak8Kit
import Gmak8XPC

enum EngineStatusAfterDisconnect {
    static func status() -> EngineStatus {
        EngineStatus(state: .stopped)
    }
}

enum StatusPresentation {
    static var kubeVirtVersion: String { KubeVirtPin.displayVersion }

    static func shortK3sVersion(_ version: String = K3sPin.version) -> String {
        var trimmed = version
        if trimmed.first == "v" {
            trimmed.removeFirst()
        }
        if let plus = trimmed.firstIndex(of: "+") {
            trimmed = String(trimmed[..<plus])
        }
        return trimmed
    }

    static func productLine(includeKubeVirt: Bool = true) -> String {
        var parts = ["gmak8", "k3s \(shortK3sVersion())"]
        if includeKubeVirt {
            parts.append("KubeVirt \(kubeVirtVersion)")
        }
        return parts.joined(separator: " · ")
    }

    static func nestedVirtLine(_ nested: Bool) -> String {
        "Nested virt: \(nested ? "Yes" : "No")"
    }

    static func metricsLine(_ vm: VMMetrics?) -> String {
        let metrics = vm ?? VMMetrics()
        let cpu = cpuPercent(metrics.cpu)
        return
            "CPU \(cpu)%   RAM \(formatGiB(metrics.ramUsed)) / \(formatGiB(metrics.ramCap)) GiB   Disk \(formatGiB(metrics.diskUsed)) / \(formatGiB(metrics.diskCap)) GiB"
    }

    static func cpuPercent(_ cpu: Double) -> Int {
        let percent = cpu <= 1.0 ? cpu * 100 : cpu
        return Int(percent.rounded())
    }

    static func formatGiB(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }
        if value >= 10 || value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
