import Foundation
import Gmak8Kit

public struct ClusterAddon: Equatable, Sendable, Identifiable {
    public var name: String
    public var ready: Bool

    public var id: String { name }

    public init(name: String, ready: Bool) {
        self.name = name
        self.ready = ready
    }
}

public struct ClusterNodeSummary: Equatable, Sendable {
    public var name: String
    public var ready: Bool
    public var kvmPresent: Bool?

    public init(name: String, ready: Bool, kvmPresent: Bool? = nil) {
        self.name = name
        self.ready = ready
        self.kvmPresent = kvmPresent
    }
}

public struct ClusterOverview: Equatable, Sendable {
    public var kubernetesVersion: String
    public var apiReady: Bool
    public var datastore: String
    public var contextName: String
    public var node: ClusterNodeSummary?
    public var addons: [ClusterAddon]

    public init(
        kubernetesVersion: String,
        apiReady: Bool,
        datastore: String = ClusterOverviewCopy.sqlite,
        contextName: String = "gmak8",
        node: ClusterNodeSummary? = nil,
        addons: [ClusterAddon] = []
    ) {
        self.kubernetesVersion = kubernetesVersion
        self.apiReady = apiReady
        self.datastore = datastore
        self.contextName = contextName
        self.node = node
        self.addons = addons
    }

    public static func sampleRunning() -> ClusterOverview {
        ClusterOverview(
            kubernetesVersion: K3sPin.version,
            apiReady: true,
            node: ClusterNodeSummary(name: "gmak8", ready: true, kvmPresent: false),
            addons: ClusterAddonMatcher.kubernetesAddons.map { ClusterAddon(name: $0, ready: true) }
        )
    }
}

public enum ClusterOverviewError: Error, Equatable, Sendable, LocalizedError {
    case kubeconfigMissing(String)
    case clientUnavailable
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .kubeconfigMissing(let path):
            return "Kubeconfig is missing at \(path)."
        case .clientUnavailable:
            return "The Kubernetes client could not load the gmak8 context."
        case .requestFailed(let message):
            return message
        }
    }
}

public protocol ClusterOverviewClient: Sendable {
    func snapshot() async throws -> ClusterOverview
}

public struct FakeClusterOverviewClient: ClusterOverviewClient {
    public var overview: ClusterOverview
    public var error: ClusterOverviewError?

    public init(overview: ClusterOverview = .sampleRunning(), error: ClusterOverviewError? = nil) {
        self.overview = overview
        self.error = error
    }

    public func snapshot() async throws -> ClusterOverview {
        if let error {
            throw error
        }
        return overview
    }
}
