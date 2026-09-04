import Gmak8Kubernetes
import SwiftUI

struct KubeVirtView: View {
    @Environment(\.sidebarReselectEpoch) private var sidebarReselectEpoch
    @EnvironmentObject private var cluster: ClusterSession
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @StateObject private var session: KubeVirtSession
    @FocusState private var filterFocused: Bool
    @State private var selected: KubeVirtRow.ID?
    @State private var path = NavigationPath()

    init() {
        _session = StateObject(wrappedValue: KubeVirtSession())
    }

    init(session: KubeVirtSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                controls
                if !cluster.status.nestedVirt, !session.filteredRows.isEmpty {
                    Text(KubeVirtCopy.nestedVirtUnsupported)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .textSelection(.enabled)
                }
                if let error = session.lastError, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                table
            }
            .navigationTitle(session.kind.title)
            .navigationDestination(for: KubeVirtRow.self) { row in
                KubeVirtDetailView(
                    kind: row.kind,
                    namespace: row.namespace,
                    name: row.name,
                    client: session.makeClient(),
                    nestedVirt: cluster.status.nestedVirt,
                    kvmPresent: cluster.status.kvmPresent,
                    onDiagnostics: { appDelegate.openRecoveryWindow() }
                )
            }
        }
        .onAppear { session.startPolling() }
        .onDisappear { session.stopPolling() }
        .onChange(of: session.kind) { _, _ in
            selected = nil
            Task { await session.refresh() }
        }
        .onChange(of: session.scope) { _, _ in
            selected = nil
            Task { await session.refresh() }
        }
        .onChange(of: selected) { _, id in
            guard let id, let row = session.filteredRows.first(where: { $0.id == id }) else {
                return
            }
            path.append(row)
        }
        .onChange(of: sidebarReselectEpoch) { _, _ in
            path = NavigationPath()
            selected = nil
        }
        .onChange(of: path.count) { _, count in
            if count == 0 {
                selected = nil
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(KubeVirtCopy.kind, selection: $session.kind) {
                ForEach(KubeVirtKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Picker(WorkloadsCopy.namespace, selection: $session.scope) {
                Text(WorkloadsCopy.allNamespaces).tag(WorkloadNamespaceScope.all)
                ForEach(session.namespaces, id: \.self) { name in
                    Text(name).tag(WorkloadNamespaceScope.named(name))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
            TextField(WorkloadsCopy.filter, text: $session.filter)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .frame(minWidth: 160)
            Button(ClusterOverviewCopy.refresh) {
                Task { await session.refresh() }
            }
            .keyboardShortcut("r")
            .disabled(session.isRefreshing)
        }
        .padding(16)
        .background {
            Button("Focus filter") { filterFocused = true }
                .keyboardShortcut("f")
                .hidden()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var table: some View {
        let rows = session.filteredRows
        if rows.isEmpty {
            Text(emptyCopy)
                .foregroundStyle(.secondary)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Table(rows, selection: $selected) {
                TableColumn("Name", value: \.name)
                TableColumn("Namespace", value: \.namespace)
                TableColumn("Status", value: \.status)
                TableColumn("Ready", value: \.ready)
                TableColumn("Age") { row in
                    Text(WorkloadAge.format(from: row.createdAt))
                }
            }
        }
    }

    private var emptyCopy: String {
        if !cluster.status.nestedVirt {
            return KubeVirtCopy.nestedVirtUnsupported
        }
        return KubeVirtCopy.empty
    }
}
