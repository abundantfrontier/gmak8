import Combine
import Foundation
import Gmak8Kit
import Gmak8Kubernetes
import Gmak8XPC

@MainActor
final class ImagesSession: ObservableObject {
    @Published var filter = ""
    @Published var showSystem = false
    @Published private(set) var items: [NodeImage] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPruning = false

    var socketURL: URL
    private var pollTask: Task<Void, Never>?

    init(socketURL: URL = HostPaths.current().engineSocket) {
        self.socketURL = socketURL
    }

    var visibleItems: [NodeImage] {
        let base = showSystem ? items : items.filter { !$0.system }
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return base
        }
        return base.filter { image in
            image.displayName.lowercased().contains(query)
                || image.id.lowercased().contains(query)
                || image.refs.contains { $0.lowercased().contains(query) }
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
        let socketURL = self.socketURL
        do {
            let list = try await Task.detached {
                try EngineClient.listImages(socketURL: socketURL)
            }.value
            items = list.items
            lastError = nil
        } catch let error as CLIError {
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func load(path: String) async {
        let socketURL = self.socketURL
        do {
            try await Task.detached {
                try EngineClient.submit(.loadImage(path: path), socketURL: socketURL)
            }.value
            lastError = nil
        } catch let error as CLIError {
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func prune() async {
        isPruning = true
        defer { isPruning = false }
        let socketURL = self.socketURL
        do {
            let list = try await Task.detached {
                try EngineClient.pruneImages(socketURL: socketURL)
            }.value
            items = list.items
            lastError = nil
        } catch let error as CLIError {
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }
}
