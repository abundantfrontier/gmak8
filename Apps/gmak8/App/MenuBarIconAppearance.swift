import Gmak8XPC

enum MenuBarIconAppearance: Equatable, Sendable {
    case grayStopped
    case blueStarting
    case filledRunning
    case yellowDegraded
    case redFailed
    case paused

    init(state: ClusterState) {
        switch state {
        case .stopped, .stopping:
            self = .grayStopped
        case .starting:
            self = .blueStarting
        case .running:
            self = .filledRunning
        case .degraded:
            self = .yellowDegraded
        case .failed:
            self = .redFailed
        case .paused:
            self = .paused
        }
    }

    var systemImage: String {
        switch self {
        case .grayStopped, .blueStarting:
            return "circle"
        case .filledRunning, .yellowDegraded, .redFailed:
            return "circle.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    var showsPauseBadge: Bool {
        self == .paused
    }
}
