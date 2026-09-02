import Gmak8XPC

enum MenuBarIconAppearance: Equatable, Sendable, CaseIterable {
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
        case .grayStopped:
            return "circle"
        case .blueStarting:
            return "circle.dotted"
        case .filledRunning:
            return "circle.fill"
        case .yellowDegraded:
            return "exclamationmark.triangle.fill"
        case .redFailed:
            return "xmark.octagon.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    var showsPauseBadge: Bool {
        self == .paused
    }
}
