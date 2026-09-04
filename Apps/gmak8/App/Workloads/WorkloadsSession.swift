import Combine
import Foundation
import Gmak8Kit
import Gmak8Kubernetes

@MainActor
final class WorkloadsSession: ObservableObject {
    @Published var kind: WorkloadKind = .pod
    @Published var scope: WorkloadNamespaceScope = .all
    @Published var filter = ""
    @Published private(set) var namespaces: [String] = []
    @Published private(set) var rows: [WorkloadRow] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    var kubeconfigURL: URL
    private let injected: (any WorkloadsClient)?
    private var pollTask: Task<Void, Never>?

    init(client: any WorkloadsClient) {
        self.injected = client
        self.kubeconfigURL = HostPaths.current().kubeconfigFile
    }

    init(kubeconfigURL: URL = HostPaths.current().kubeconfigFile) {
        self.injected = nil
        self.kubeconfigURL = kubeconfigURL
    }

    var filteredRows: [WorkloadRow] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { row in
            row.name.lowercased().contains(query)
                || row.namespace.lowercased().contains(query)
                || row.status.lowercased().contains(query)
        }
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
        let client = makeClient()
        do {
            namespaces = try await client.namespaces()
            rows = try await client.list(kind: kind, scope: scope)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func makeClient() -> any WorkloadsClient {
        injected ?? SwiftkubeWorkloadsClient(kubeconfigURL: kubeconfigURL)
    }
}
