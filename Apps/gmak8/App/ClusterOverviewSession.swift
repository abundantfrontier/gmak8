import Combine
import Foundation
import Gmak8Kit
import Gmak8Kubernetes

@MainActor
final class ClusterOverviewSession: ObservableObject {
    @Published private(set) var overview: ClusterOverview?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    var includeEureka = false
    var kubeconfigURL: URL

    private let injected: (any ClusterOverviewClient)?
    private var pollTask: Task<Void, Never>?

    init(client: any ClusterOverviewClient) {
        self.injected = client
        self.kubeconfigURL = HostPaths.current().kubeconfigFile
    }

    init(kubeconfigURL: URL = HostPaths.current().kubeconfigFile, includeEureka: Bool = false) {
        self.injected = nil
        self.kubeconfigURL = kubeconfigURL
        self.includeEureka = includeEureka
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let client: any ClusterOverviewClient =
            injected
            ?? SwiftkubeClusterOverviewClient(
                kubeconfigURL: kubeconfigURL,
                includeEureka: includeEureka
            )
        do {
            overview = try await client.snapshot()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
