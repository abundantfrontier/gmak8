import Foundation
import Gmak8Kit
import SwiftkubeClient
import SwiftkubeModel

public struct SwiftkubeWorkloadsClient: WorkloadsClient {
    public var kubeconfigURL: URL
    public var contextName: String

    public init(
        kubeconfigURL: URL = HostPaths.current().kubeconfigFile,
        contextName: String = "gmak8"
    ) {
        self.kubeconfigURL = kubeconfigURL
        self.contextName = contextName
    }

    public func namespaces() async throws -> [String] {
        try await withClient { client in
            let list = try await client.namespaces.list()
            return list.items.compactMap(\.metadata?.name).sorted()
        }
    }

    public func list(kind: WorkloadKind, scope: WorkloadNamespaceScope) async throws -> [WorkloadRow] {
        try await withClient { client in
            let ns = namespaceSelector(scope)
            switch kind {
            case .pod:
                let list = try await client.pods.list(in: ns)
                return list.items.map { pod in
                    let statuses = pod.status?.containerStatuses ?? []
                    let readyCount = statuses.filter { $0.ready }.count
                    let phase = pod.status?.phase ?? "Unknown"
                    return WorkloadRow(
                        kind: .pod,
                        namespace: pod.metadata?.namespace ?? "",
                        name: pod.metadata?.name ?? "",
                        status: phase,
                        ready: "\(readyCount)/\(max(statuses.count, 1))",
                        createdAt: pod.metadata?.creationTimestamp
                    )
                }
            case .deployment:
                let list = try await client.appsV1.deployments.list(in: ns)
                return list.items.map { item in
                    let ready = item.status?.readyReplicas ?? 0
                    let total = item.spec?.replicas ?? 0
                    return WorkloadRow(
                        kind: .deployment,
                        namespace: item.metadata?.namespace ?? "",
                        name: item.metadata?.name ?? "",
                        status: ready >= total && total > 0 ? "Ready" : "Not ready",
                        ready: "\(ready)/\(total)",
                        createdAt: item.metadata?.creationTimestamp
                    )
                }
            case .statefulSet:
                let list = try await client.appsV1.statefulSets.list(in: ns)
                return list.items.map { item in
                    let ready = item.status?.readyReplicas ?? 0
                    let total = item.spec?.replicas ?? 0
                    return WorkloadRow(
                        kind: .statefulSet,
                        namespace: item.metadata?.namespace ?? "",
                        name: item.metadata?.name ?? "",
                        status: ready >= total && total > 0 ? "Ready" : "Not ready",
                        ready: "\(ready)/\(total)",
                        createdAt: item.metadata?.creationTimestamp
                    )
                }
            case .daemonSet:
                let list = try await client.appsV1.daemonSets.list(in: ns)
                return list.items.map { item in
                    let ready = item.status?.numberReady ?? 0
                    let total = item.status?.desiredNumberScheduled ?? 0
                    return WorkloadRow(
                        kind: .daemonSet,
                        namespace: item.metadata?.namespace ?? "",
                        name: item.metadata?.name ?? "",
                        status: ready >= total && total > 0 ? "Ready" : "Not ready",
                        ready: "\(ready)/\(total)",
                        createdAt: item.metadata?.creationTimestamp
                    )
                }
            case .job:
                let list = try await client.batchV1.jobs.list(in: ns)
                return list.items.map { item in
                    let succeeded = item.status?.succeeded ?? 0
                    let completions = item.spec?.completions ?? 1
                    return WorkloadRow(
                        kind: .job,
                        namespace: item.metadata?.namespace ?? "",
                        name: item.metadata?.name ?? "",
                        status: succeeded >= completions ? "Complete" : "Running",
                        ready: "\(succeeded)/\(completions)",
                        createdAt: item.metadata?.creationTimestamp
                    )
                }
            case .cronJob:
                let list = try await client.batchV1.cronJobs.list(in: ns)
                return list.items.map { item in
                    let active = item.status?.active?.count ?? 0
                    return WorkloadRow(
                        kind: .cronJob,
                        namespace: item.metadata?.namespace ?? "",
                        name: item.metadata?.name ?? "",
                        status: active > 0 ? "Active" : "Idle",
                        ready: "\(active)",
                        createdAt: item.metadata?.creationTimestamp
                    )
                }
            }
        }
    }

    public func pod(namespace: String, name: String) async throws -> PodDetail {
        try await withClient { client in
            let pod = try await client.pods.get(in: .namespace(namespace), name: name)
            let events = try await client.events.list(
                in: .namespace(namespace),
                options: [.fieldSelector(.eq(["involvedObject.name": name]))]
            )
            let statuses = pod.status?.containerStatuses ?? []
            let specs = pod.spec?.containers ?? []
            let containers: [PodContainerInfo] = specs.map { spec in
                let status = statuses.first { $0.name == spec.name }
                let env: [PodEnvVar] = (spec.env ?? []).map { variable in
                    PodEnvVar(
                        name: variable.name,
                        display: SecretRedactor.envDisplay(
                            value: variable.value,
                            secretName: variable.valueFrom?.secretKeyRef?.name,
                            secretKey: variable.valueFrom?.secretKeyRef?.key
                        )
                    )
                }
                return PodContainerInfo(
                    name: spec.name,
                    image: spec.image ?? "",
                    ready: status?.ready ?? false,
                    restarts: Int(status?.restartCount ?? 0),
                    env: env
                )
            }
            let ready =
                pod.status?.conditions?.contains { ($0.type == "Ready") && ($0.status == "True") } ?? false
            return PodDetail(
                namespace: namespace,
                name: name,
                phase: pod.status?.phase ?? "Unknown",
                ready: ready,
                nodeName: pod.spec?.nodeName,
                containers: containers,
                yaml: try SecretRedactor.yaml(pod),
                events: events.items.map { event in
                    PodEvent(
                        type: event.type ?? "",
                        reason: event.reason ?? "",
                        message: event.message ?? "",
                        count: Int(event.count ?? 1),
                        lastSeen: event.lastTimestamp ?? event.eventTime
                    )
                }
            )
        }
    }

    public func podLogs(namespace: String, name: String, container: String?, tailLines: Int) async throws
        -> String
    {
        try await withClient { client in
            let raw = try await client.pods.logs(
                in: .namespace(namespace),
                name: name,
                container: container,
                tailLines: tailLines
            )
            return PodLogCap.clipped(raw)
        }
    }

    private func namespaceSelector(_ scope: WorkloadNamespaceScope) -> NamespaceSelector {
        switch scope {
        case .all:
            return .allNamespaces
        case .named(let name):
            return .namespace(name)
        }
    }

    private func withClient<T: Sendable>(_ work: (KubernetesClient) async throws -> T) async throws -> T {
        let path = kubeconfigURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ClusterOverviewError.kubeconfigMissing(path)
        }
        let kubeConfig: KubeConfig
        do {
            kubeConfig = try KubeConfig.from(url: kubeconfigURL)
        } catch {
            throw ClusterOverviewError.requestFailed(error.localizedDescription)
        }
        guard let client = KubernetesClient(kubeConfig: kubeConfig, contextName: contextName) else {
            throw ClusterOverviewError.clientUnavailable
        }
        defer { try? client.syncShutdown() }
        do {
            return try await work(client)
        } catch let error as ClusterOverviewError {
            throw error
        } catch {
            throw ClusterOverviewError.requestFailed(error.localizedDescription)
        }
    }
}
