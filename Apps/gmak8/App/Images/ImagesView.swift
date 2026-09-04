import AppKit
import Gmak8Kubernetes
import Gmak8XPC
import SwiftUI
import UniformTypeIdentifiers

struct ImagesView: View {
    @EnvironmentObject private var cluster: ClusterSession
    @StateObject private var session: ImagesSession
    @FocusState private var filterFocused: Bool
    @State private var confirmPrune = false

    init() {
        _session = StateObject(wrappedValue: ImagesSession())
    }

    init(session: ImagesSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            if let job = cluster.status.imageJob {
                jobBanner(job)
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
        .navigationTitle(ImagesCopy.title)
        .onAppear { session.startPolling() }
        .onDisappear { session.stopPolling() }
        .onChange(of: cluster.status.imageJob?.bytesReceived) { _, _ in
            if cluster.status.imageJob == nil {
                Task { await session.refresh() }
            }
        }
        .confirmationDialog(ImagesCopy.pruneConfirm, isPresented: $confirmPrune, titleVisibility: .visible) {
            Button(ImagesCopy.prune, role: .destructive) {
                Task { await session.prune() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(ImagesCopy.load) {
                pickAndLoad()
            }
            .disabled(cluster.status.imageJob != nil)
            Button(ImagesCopy.prune) {
                confirmPrune = true
            }
            .disabled(session.isPruning || cluster.status.imageJob != nil)
            Button(ImagesCopy.build) {}
                .disabled(true)
                .help(ImagesCopy.buildUnavailable)
            Toggle(ImagesCopy.showSystem, isOn: $session.showSystem)
                .toggleStyle(.checkbox)
            TextField(ImagesCopy.filter, text: $session.filter)
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
        let rows = session.visibleItems
        if rows.isEmpty {
            Text(ImagesCopy.empty)
                .foregroundStyle(.secondary)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Table(rows) {
                TableColumn(ImagesCopy.name, value: \.displayName)
                TableColumn(ImagesCopy.digest) { image in
                    Text(shortDigest(image.id))
                        .textSelection(.enabled)
                }
                TableColumn(ImagesCopy.size) { image in
                    Text(NodeImageRow.formatBytes(image.sizeBytes))
                }
            }
        }
    }

    private func jobBanner(_ job: ImageJobStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.importing ? ImagesCopy.importing : ImagesCopy.receiving)
                .font(.caption)
            if let total = job.bytesTotal, total > 0 {
                ProgressView(value: Double(job.bytesReceived), total: Double(total))
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func pickAndLoad() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "tar"),
            UTType(filenameExtension: "gz"),
            .data,
        ].compactMap { $0 }
        panel.message = "Choose an OCI or Docker image tar."
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let path = url.path(percentEncoded: false)
        Task { await session.load(path: path) }
    }

    private func shortDigest(_ id: String) -> String {
        if id.hasPrefix("sha256:"), id.count > 19 {
            return String(id.prefix(19)) + "…"
        }
        return id
    }
}
