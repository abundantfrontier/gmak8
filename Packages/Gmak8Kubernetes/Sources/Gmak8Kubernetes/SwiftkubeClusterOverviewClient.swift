import Foundation
import Gmak8Kit
import SwiftkubeClient
import SwiftkubeModel

public struct SwiftkubeClusterOverviewClient: ClusterOverviewClient {
    public var kubeconfigURL: URL
    public var contextName: String
    public var includeEureka: Bool

    public init(
        kubeconfigURL: URL = HostPaths.current().kubeconfigFile,
        contextName: String = "gmak8",
        includeEureka: Bool = false
    ) {
        self.kubeconfigURL = kubeconfigURL
        self.contextName = contextName
        self.includeEureka = includeEureka
    }

    public func snapshot() async throws -> ClusterOverview {
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
            let version = try await client.discoveryClient.serverVersion()
            let nodes = try await client.nodes.list()
            let deployments = try await client.appsV1.deployments.list(in: .namespace("kube-system"))
            let daemonSets = try await client.appsV1.daemonSets.list(in: .namespace("kube-system"))
            var readyByName: [String: Bool] = [:]
            for item in deployments.items {
                let name = item.metadata?.name ?? ""
                guard let addon = ClusterAddonMatcher.classify(workloadName: name) else {
                    continue
                }
                let ready = (item.status?.readyReplicas ?? 0) >= 1
                readyByName[addon] = (readyByName[addon] ?? false) || ready
            }
            for item in daemonSets.items {
                let name = item.metadata?.name ?? ""
                guard let addon = ClusterAddonMatcher.classify(workloadName: name) else {
                    continue
                }
                let ready = (item.status?.numberReady ?? 0) >= 1
                readyByName[addon] = (readyByName[addon] ?? false) || ready
            }
            if includeEureka {
                let crds = try? await client.apiExtensionsV1.customResourceDefinitions.list()
                if let crds {
                    let names = crds.items.compactMap { $0.metadata?.name?.lowercased() }
                    if names.contains(where: { $0.contains("kubevirt") }) {
                        readyByName["KubeVirt"] = readyByName["KubeVirt"] ?? true
                    }
                    if names.contains(where: { $0.contains("datavolume") || $0.contains("cdi") }) {
                        readyByName["CDI"] = readyByName["CDI"] ?? true
                    }
                    if names.contains(where: { $0.contains("instancetype") }) {
                        readyByName["common-instancetypes"] = true
                    }
                }
            }
            let node = nodes.items.first.map { item in
                let name = item.metadata?.name ?? "gmak8"
                let ready =
                    item.status?.conditions?.contains {
                        ($0.type == "Ready") && ($0.status == "True")
                    } ?? false
                return ClusterNodeSummary(name: name, ready: ready)
            }
            return ClusterOverview(
                kubernetesVersion: version.gitVersion,
                apiReady: true,
                node: node,
                addons: ClusterAddonMatcher.addons(readyByName: readyByName, includeEureka: includeEureka)
            )
        } catch let error as ClusterOverviewError {
            throw error
        } catch {
            throw ClusterOverviewError.requestFailed(error.localizedDescription)
        }
    }
}
