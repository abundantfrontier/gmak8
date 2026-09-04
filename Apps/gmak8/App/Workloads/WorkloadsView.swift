import Gmak8Kubernetes
import SwiftUI

struct WorkloadsView: View {
    @Environment(\.sidebarReselectEpoch) private var sidebarReselectEpoch
    @StateObject private var session: WorkloadsSession
    @FocusState private var filterFocused: Bool
    @State private var selected: WorkloadRow.ID?
    @State private var path = NavigationPath()

    init() {
        _session = StateObject(wrappedValue: WorkloadsSession())
    }

    init(session: WorkloadsSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                controls
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
            .navigationDestination(for: WorkloadRow.self) { row in
                if row.kind == .pod {
                    PodDetailView(
                        namespace: row.namespace,
                        name: row.name,
                        client: session.makeClient()
                    )
                } else {
                    workloadSummary(row)
                }
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
            popToList()
        }
        .onChange(of: path.count) { _, count in
            if count == 0 {
                selected = nil
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(WorkloadsCopy.kind, selection: $session.kind) {
                ForEach(WorkloadKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 180)
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
            Text(WorkloadsCopy.empty)
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

    private func workloadSummary(_ row: WorkloadRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.name)
                .font(.title2)
                .fontWeight(.semibold)
            Text("\(row.kind.title) · \(row.namespace) · \(row.status) · \(row.ready)")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(row.name)
    }

    private func popToList() {
        path = NavigationPath()
        selected = nil
    }
}
