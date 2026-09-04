import Gmak8Kit
import Gmak8Kubernetes
import Gmak8XPC
import SwiftUI

struct ClusterOverviewView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @ObservedObject var overview: ClusterOverviewSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 16) {
                    controlPlaneCard
                    nodeCard
                }
                metersCard
                addonsCard
                portsCard
                HStack {
                    Button("Stop") {
                        session.stopCluster()
                    }
                    .disabled(!session.canStop)
                    Button("Diagnostics") {
                        appDelegate.openRecoveryWindow()
                    }
                    Button("Reset…") {
                        appDelegate.confirmAndResetCluster()
                    }
                    Spacer()
                    Button(ClusterOverviewCopy.refresh) {
                        Task { await overview.refresh() }
                    }
                    .keyboardShortcut("r")
                    .disabled(overview.isRefreshing)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(ClusterOverviewCopy.cluster)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(StatusText.displayName(session.status.state))
                .font(.title2)
                .fontWeight(.semibold)
            Text(headerLine)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(StatusPresentation.nestedVirtLine(session.status.nestedVirt))
                .font(.caption)
            if let error = session.status.lastError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if let error = overview.lastError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    private var headerLine: String {
        let version = overview.overview?.kubernetesVersion ?? K3sPin.version
        let context = overview.overview?.contextName ?? "gmak8"
        let api = session.status.apiEndpoint ?? "https://127.0.0.1:6443"
        return "\(version) · \(ClusterOverviewCopy.context) \(context) · \(api)"
    }

    private var controlPlaneCard: some View {
        overviewCard(title: ClusterOverviewCopy.controlPlane) {
            labeled(ClusterOverviewCopy.sqlite, ClusterOverviewCopy.sqlite)
            let ready = overview.overview?.apiReady ?? false
            labeled(
                ClusterOverviewCopy.readyz,
                ready ? ClusterOverviewCopy.apiReady : ClusterOverviewCopy.apiNotReady
            )
        }
    }

    private var nodeCard: some View {
        overviewCard(title: ClusterOverviewCopy.node) {
            if let node = overview.overview?.node {
                labeled(node.name, node.ready ? ClusterOverviewCopy.nodeReady : ClusterOverviewCopy.nodeNotReady)
                labeled("kvm", kvmLine(session.status.kvmPresent ?? node.kvmPresent))
            } else {
                Text(ClusterOverviewCopy.noNode)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metersCard: some View {
        overviewCard(title: ClusterOverviewCopy.meters) {
            Text(StatusPresentation.metricsLine(session.status.vm))
                .textSelection(.enabled)
        }
    }

    private var addonsCard: some View {
        overviewCard(title: ClusterOverviewCopy.addons) {
            if let addons = overview.overview?.addons, !addons.isEmpty {
                ForEach(addons) { addon in
                    labeled(addon.name, addon.ready ? ClusterOverviewCopy.apiReady : ClusterOverviewCopy.apiNotReady)
                }
            } else {
                Text(ClusterOverviewCopy.addonsPending)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var portsCard: some View {
        overviewCard(title: ClusterOverviewCopy.publishedPorts) {
            let ports = session.status.publishedPorts
            if ports.isEmpty {
                Text(ClusterOverviewCopy.noPublishedPorts)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                    labeled(port.service, port.hostURL)
                }
            }
        }
    }

    private func kvmLine(_ present: Bool?) -> String {
        switch present {
        case .some(true):
            return ClusterOverviewCopy.kvmPresent
        case .some(false):
            return ClusterOverviewCopy.kvmMissing
        case .none:
            return ClusterOverviewCopy.kvmUnknown
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func overviewCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}
