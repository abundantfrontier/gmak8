import Foundation
import Gmak8Kit
import SwiftkubeClient
import SwiftkubeModel

public struct SwiftkubeKubeVirtClient: KubeVirtClient {
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

    public func list(kind: KubeVirtKind, scope: WorkloadNamespaceScope) async throws -> [KubeVirtRow] {
        try await withClient { client in
            let list = try await client.for(gvr: gvr(kind)).list(in: namespaceSelector(scope))
            return list.items.map { resource in
                row(kind: kind, resource: resource)
            }
        }
    }

    public func detail(kind: KubeVirtKind, namespace: String, name: String) async throws -> KubeVirtDetail {
        try await withClient { client in
            let resource = try await client.for(gvr: gvr(kind)).get(in: .namespace(namespace), name: name)
            let events = try await client.events.list(
                in: .namespace(namespace),
                options: [
                    .fieldSelector(
                        .eq([
                            "involvedObject.name": name,
                            "involvedObject.kind": kind.resourceKind,
                        ]))
                ]
            )
            return try detail(
                kind: kind,
                resource: resource,
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

    public func setRunning(namespace: String, name: String, running: Bool) async throws -> KubeVirtDetail {
        try await withClient { client in
            let generic = client.for(gvr: gvr(.virtualMachine))
            let resource = try await generic.get(in: .namespace(namespace), name: name)
            let updated = try withRunning(resource, running: running)
            let saved = try await generic.update(in: .namespace(namespace), updated)
            let events = try await client.events.list(
                in: .namespace(namespace),
                options: [
                    .fieldSelector(
                        .eq([
                            "involvedObject.name": name,
                            "involvedObject.kind": KubeVirtKind.virtualMachine.resourceKind,
                        ]))
                ]
            )
            return try detail(
                kind: .virtualMachine,
                resource: saved,
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

    private func gvr(_ kind: KubeVirtKind) -> GroupVersionResource {
        GroupVersionResource(group: kind.apiGroup, version: kind.apiVersion, resource: kind.plural)
    }

    private func namespaceSelector(_ scope: WorkloadNamespaceScope) -> NamespaceSelector {
        switch scope {
        case .all:
            return .allNamespaces
        case .named(let name):
            return .namespace(name)
        }
    }

    private func row(kind: KubeVirtKind, resource: UnstructuredResource) -> KubeVirtRow {
        let object = jsonObject(resource)
        let spec = KubeVirtFields.dictionary(object["spec"]) ?? [:]
        let status = KubeVirtFields.dictionary(object["status"]) ?? [:]
        let metadata = resource.metadata
        return KubeVirtFields.row(
            kind: kind,
            namespace: metadata?.namespace ?? "",
            name: metadata?.name ?? "",
            spec: spec,
            status: status,
            createdAt: metadata?.creationTimestamp
        )
    }

    private func detail(kind: KubeVirtKind, resource: UnstructuredResource, events: [PodEvent]) throws
        -> KubeVirtDetail
    {
        let object = jsonObject(resource)
        let spec = KubeVirtFields.dictionary(object["spec"]) ?? [:]
        let status = KubeVirtFields.dictionary(object["status"]) ?? [:]
        let metadata = resource.metadata
        return KubeVirtFields.detail(
            kind: kind,
            namespace: metadata?.namespace ?? "",
            name: metadata?.name ?? "",
            spec: spec,
            status: status,
            events: events,
            yaml: try SecretRedactor.yaml(resource)
        )
    }

    private func withRunning(_ resource: UnstructuredResource, running: Bool) throws -> UnstructuredResource {
        var object = jsonObject(resource)
        let spec = KubeVirtFields.dictionary(object["spec"]) ?? [:]
        object["spec"] = KubeVirtFields.withRunning(spec, running: running)
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UnstructuredResource.self, from: data)
    }

    private func jsonObject(_ resource: UnstructuredResource) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(resource),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
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
        guard let client = SwiftkubeClientFactory.make(kubeConfig: kubeConfig, contextName: contextName)
        else {
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
