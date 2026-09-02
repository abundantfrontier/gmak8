import Combine
import Foundation
import Gmak8Kit
import Gmak8XPC

@MainActor
final class ClusterSession: ObservableObject, @unchecked Sendable {
    @Published private(set) var status = EngineStatus(state: .stopped)
    @Published private(set) var connectionError: CLIError?

    private let socketURL: URL
    private let fileManager: FileManager
    private var subscription: EngineSubscription?
    private var listenTask: Task<Void, Never>?

    init(
        socketURL: URL = HostPaths.current().engineSocket,
        fileManager: FileManager = .default
    ) {
        self.socketURL = socketURL
        self.fileManager = fileManager
    }

    var canStart: Bool {
        switch status.state {
        case .stopped, .failed:
            return true
        case .starting, .running, .degraded, .paused, .stopping:
            return false
        }
    }

    var canStop: Bool {
        status.state != .stopped
    }

    func startListening() {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            await self?.listenLoop()
        }
    }

    func stopListening() {
        listenTask?.cancel()
        listenTask = nil
        subscription?.cancel()
        subscription = nil
    }

    func startCluster(waitForEngine: Bool = false) {
        ensureCoreAgentRegistered()
        if waitForEngine {
            Task { await self.submitStartWhenEngineReady() }
            return
        }
        submit(.start)
    }

    func stopCluster() {
        submit(.stop)
    }

    func stopClusterBestEffort() async {
        do {
            let socketURL = self.socketURL
            try await Task.detached {
                try EngineClient.submit(.stop, socketURL: socketURL)
            }.value
            connectionError = nil
        } catch let error as CLIError where error == .engineNotRunning {
            markDisconnected(.engineNotRunning)
            connectionError = nil
        } catch let error as CLIError {
            connectionError = error
        } catch {
            connectionError = .communicationFailed
        }
    }

    private func submitStartWhenEngineReady() async {
        let socketURL = self.socketURL
        var remaining = EngineReadyPoll.defaultAttempts
        while remaining > 0 {
            do {
                try await Task.detached {
                    try EngineClient.submit(.start, socketURL: socketURL)
                }.value
                connectionError = nil
                return
            } catch let error as CLIError where error == .engineNotRunning {
                remaining -= 1
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch let error as CLIError {
                markDisconnected(error)
                return
            } catch {
                markDisconnected(.communicationFailed)
                return
            }
        }
        markDisconnected(.engineNotRunning)
    }

    private func submit(_ request: EngineRequest) {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let socketURL = self.socketURL
                try await Task.detached {
                    try EngineClient.submit(request, socketURL: socketURL)
                }.value
                self.connectionError = nil
            } catch let error as CLIError {
                self.markDisconnected(error)
            } catch {
                self.markDisconnected(.communicationFailed)
            }
        }
    }

    private func listenLoop() async {
        while !Task.isCancelled {
            subscription?.cancel()
            subscription = nil
            if !fileManager.fileExists(atPath: socketURL.path(percentEncoded: false)) {
                markDisconnected(.engineNotRunning)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            do {
                let socketURL = self.socketURL
                let subscription = try await Task.detached { [weak self] in
                    try EngineClient.subscribe(
                        socketURL: socketURL,
                        onEvent: { event in
                            Task { @MainActor in
                                self?.handle(event)
                            }
                        },
                        onError: { error in
                            Task { @MainActor in
                                self?.handleConnectionError(error)
                            }
                        }
                    )
                }.value
                self.subscription = subscription
                await subscription.waitUntilStopped()
            } catch let error as CLIError {
                handleConnectionError(error)
            } catch {
                handleConnectionError(.communicationFailed)
            }
            if Task.isCancelled {
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func handle(_ event: EngineEvent) {
        connectionError = nil
        if case .status(let status) = event {
            self.status = status
        }
    }

    private func handleConnectionError(_ error: CLIError) {
        if Task.isCancelled {
            return
        }
        markDisconnected(error)
    }

    private func markDisconnected(_ error: CLIError) {
        connectionError = error
        if error.resetsClusterStatus {
            status = EngineStatusAfterDisconnect.status()
        }
    }

    private func ensureCoreAgentRegistered() {
        do {
            try LaunchAtLoginPolicy.apply(
                LaunchAtLoginPolicy.extraDidLaunch(),
                bundleURL: Bundle.main.bundleURL
            )
        } catch {
            return
        }
    }
}
