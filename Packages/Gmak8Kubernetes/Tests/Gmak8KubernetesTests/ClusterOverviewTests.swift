import Foundation
import Gmak8Kit
import Testing

@testable import Gmak8Kubernetes

struct ClusterOverviewTests {
    @Test func fakeClientReturnsPinnedOverview() async throws {
        let fake = FakeClusterOverviewClient(overview: .sampleRunning())
        let snapshot = try await fake.snapshot()
        #expect(snapshot.apiReady)
        #expect(snapshot.contextName == "gmak8")
        #expect(snapshot.datastore == ClusterOverviewCopy.sqlite)
        #expect(snapshot.kubernetesVersion == K3sPin.version)
        #expect(snapshot.node?.name == "gmak8")
        #expect(snapshot.node?.ready == true)
        #expect(snapshot.addons.map(\.name) == ClusterAddonMatcher.kubernetesAddons)
        #expect(snapshot.addons.allSatisfy { $0.ready })
    }

    @Test func fakeClientSurfacesMissingKubeconfig() async {
        let fake = FakeClusterOverviewClient(error: .kubeconfigMissing("/tmp/missing"))
        do {
            _ = try await fake.snapshot()
            Issue.record("expected missing kubeconfig")
        } catch let error as ClusterOverviewError {
            #expect(error == .kubeconfigMissing("/tmp/missing"))
            #expect(error.errorDescription?.contains("/tmp/missing") == true)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func matcherClassifiesKubeSystemWorkloads() {
        #expect(ClusterAddonMatcher.classify(workloadName: "coredns-abc") == "CoreDNS")
        #expect(ClusterAddonMatcher.classify(workloadName: "traefik") == "Traefik")
        #expect(ClusterAddonMatcher.classify(workloadName: "metrics-server") == "metrics-server")
        #expect(ClusterAddonMatcher.classify(workloadName: "local-path-provisioner") == "local-path")
        #expect(ClusterAddonMatcher.classify(workloadName: "svclb-traefik-xyz") == "ServiceLB")
        #expect(ClusterAddonMatcher.classify(workloadName: "helm-install-traefik") == nil)
        #expect(ClusterAddonMatcher.classify(workloadName: "virt-operator") == "KubeVirt")
        #expect(ClusterAddonMatcher.classify(workloadName: "cdi-apiserver") == "CDI")
        #expect(
            ClusterAddonMatcher.classify(workloadName: "common-instancetypes") == "common-instancetypes"
        )
    }

    @Test func matcherListsEurekaAddonsOnlyWhenAsked() {
        let kube = ClusterAddonMatcher.addons(readyByName: ["CoreDNS": true], includeEureka: false)
        #expect(kube.map(\.name) == ClusterAddonMatcher.kubernetesAddons)
        #expect(kube.first { $0.name == "CoreDNS" }?.ready == true)
        #expect(kube.first { $0.name == "Traefik" }?.ready == false)
        let eureka = ClusterAddonMatcher.names(includeEureka: true)
        #expect(eureka.contains("KubeVirt"))
        #expect(eureka.contains("CDI"))
        #expect(eureka.contains("common-instancetypes"))
        #expect(!ClusterAddonMatcher.names(includeEureka: false).contains("KubeVirt"))
    }

    @Test func sidebarCopyIsAffirmative() {
        #expect(ClusterOverviewCopy.cluster == "Cluster")
        #expect(ClusterOverviewCopy.workloadsEmpty.contains("Apply a manifest"))
        #expect(!ClusterOverviewCopy.workloadsEmpty.lowercased().contains("coming soon"))
        #expect(ClusterOverviewCopy.sqlite == "SQLite")
        #expect(ClusterOverviewCopy.readyz == "/readyz")
        #expect(!ClusterSidebarItem.visible(for: .kubernetes).contains(.kubeVirt))
        #expect(ClusterSidebarItem.visible(for: .eureka).contains(.kubeVirt))
    }
}
