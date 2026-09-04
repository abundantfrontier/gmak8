import Foundation
import Testing

@testable import Gmak8Kubernetes

struct KubeVirtObjectsTests {
    @Test func copyMatchesDesignAndOmitsOODAndSSH() {
        #expect(KubeVirtKind.allCases.map(\.title) == ["VirtualMachines", "VMIs", "VMPools", "DataVolumes"])
        #expect(KubeVirtKind.allCases.first == .virtualMachine)
        #expect(KubeVirtCopy.nestedVirtUnsupported.contains("M3"))
        #expect(KubeVirtCopy.nestedVirtUnsupported.contains("macOS 15"))
        #expect(KubeVirtCopy.nestedVirtUnsupported.contains("Pending"))
        #expect(KubeVirtCopy.empty.contains("VirtualMachine"))
        let joined = [
            KubeVirtCopy.empty, KubeVirtCopy.nestedVirtUnsupported, KubeVirtCopy.start, KubeVirtCopy.stop,
        ].joined(separator: " ").lowercased()
        #expect(!joined.contains("open ondemand"))
        #expect(!joined.contains("ood"))
        #expect(!joined.contains("ssh"))
        #expect(!joined.contains("expose"))
        #expect(!joined.contains("virtctl"))
    }

    @Test func fakeListsKindsAndNamespaces() async throws {
        let client = FakeKubeVirtClient()
        let vms = try await client.list(kind: .virtualMachine, scope: .all)
        #expect(vms.map(\.name) == ["cirros"])
        let none = try await client.list(kind: .virtualMachine, scope: .named("kube-system"))
        #expect(none.isEmpty)
        let vmis = try await client.list(kind: .virtualMachineInstance, scope: .all)
        #expect(vmis.first?.status == "Pending")
        let pools = try await client.list(kind: .virtualMachinePool, scope: .all)
        #expect(pools.first?.ready == "1/1")
        let dvs = try await client.list(kind: .dataVolume, scope: .all)
        #expect(dvs.first?.status == "Succeeded")
        let pending = try await client.detail(
            kind: .virtualMachineInstance, namespace: "default", name: "cirros")
        #expect(pending.pendingUnschedulable)
        #expect(pending.conditions.contains { $0.reason.contains("Unschedulable") })
        let started = try await client.setRunning(namespace: "default", name: "cirros", running: true)
        #expect(started.running == true)
    }

    @Test func fieldsParseVMInstancetypeDataVolumesAndRunStrategy() {
        let spec: [String: Any] = [
            "running": true,
            "instancetype": [
                "kind": "VirtualMachineClusterInstancetype",
                "name": "u1.nano",
            ],
            "dataVolumeTemplates": [
                ["metadata": ["name": "cirros-dv"]]
            ],
            "template": [
                "spec": [
                    "volumes": [
                        ["dataVolume": ["name": "cirros-dv"]],
                        ["containerDisk": ["image": "fedora"]],
                    ]
                ]
            ],
        ]
        let status: [String: Any] = [
            "printableStatus": "Running",
            "ready": true,
        ]
        let row = KubeVirtFields.row(
            kind: .virtualMachine, namespace: "default", name: "cirros", spec: spec, status: status)
        #expect(row.status == "Running")
        #expect(row.ready == "True")
        #expect(KubeVirtFields.instancetypeName(spec) == "VirtualMachineClusterInstancetype/u1.nano")
        #expect(
            KubeVirtFields.dataVolumeNames(kind: .virtualMachine, name: "cirros", spec: spec) == ["cirros-dv"])
        let halted = KubeVirtFields.withRunning(["runStrategy": "Always"], running: false)
        #expect(halted["runStrategy"] as? String == "Halted")
        #expect(halted["running"] == nil)
        let flagged = KubeVirtFields.withRunning(["running": true], running: false)
        #expect(flagged["running"] as? Bool == false)
    }

    @Test func pendingUnschedulableDetectsKvmAndVirtLauncher() {
        let conditions = [
            KubeVirtCondition(
                type: "Ready",
                status: "False",
                reason: "VirtLauncher.Unschedulable",
                message: "missing /dev/kvm"
            )
        ]
        #expect(KubeVirtFields.isPendingUnschedulable(phase: "Pending", conditions: conditions))
        #expect(!KubeVirtFields.isPendingUnschedulable(phase: "Running", conditions: conditions))
        #expect(!KubeVirtFields.isPendingUnschedulable(phase: "Pending", conditions: []))
        let vmiStatus: [String: Any] = ["phase": "Pending"]
        #expect(
            KubeVirtFields.phase(kind: .virtualMachineInstance, spec: [:], status: vmiStatus) == "Pending")
        #expect(!KubeVirtFields.isReady(kind: .virtualMachineInstance, spec: [:], status: vmiStatus))
    }

    @Test func sidebarShowsKubeVirtWhenAddonIsOn() {
        #expect(!ClusterSidebarItem.visible(for: .kubernetes).contains(.kubeVirt))
        #expect(ClusterSidebarItem.visible(for: .eureka).contains(.kubeVirt))
        #expect(
            ClusterSidebarItem.visible(for: .kubernetes, kubeVirtEnabled: true).contains(.kubeVirt)
        )
        #expect(
            !ClusterSidebarItem.visible(for: .kubernetes, kubeVirtEnabled: false).contains(.kubeVirt)
        )
    }
}
