import Gmak8Kubernetes
import SwiftUI

struct PodDetailView: View {
    let namespace: String
    let name: String
    let client: any WorkloadsClient

    @State private var detail: PodDetail?
    @State private var logs = ""
    @State private var selectedContainer: String?
    @State private var pane = PodDetailPane.status
    @State private var lastError: String?
    @State private var localPort = "18080"
    @State private var remotePort = "80"
    @FocusState private var logsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = lastError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Picker("Pane", selection: $pane) {
                Text(WorkloadsCopy.status).tag(PodDetailPane.status)
                Text(WorkloadsCopy.logs).tag(PodDetailPane.logs)
                Text(WorkloadsCopy.events).tag(PodDetailPane.events)
                Text(WorkloadsCopy.yaml).tag(PodDetailPane.yaml)
            }
            .pickerStyle(.segmented)
            .onChange(of: pane) { _, newValue in
                if newValue == .logs {
                    logsFocused = true
                }
            }
            switch pane {
            case .status:
                ScrollView {
                    statusPane
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .logs:
                logsPane
            case .events:
                eventsPane
            case .yaml:
                ScrollView {
                    Text(detail?.yaml ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(name)
        .toolbar {
            ToolbarItemGroup {
                Button(WorkloadsCopy.openShell) {
                    TerminalLauncher.openExec(namespace: namespace, pod: name, container: selectedContainer)
                }
                .disabled(!isRunning)
                .help(isRunning ? WorkloadsCopy.openShell : WorkloadsCopy.podNotRunning)
                Button(ClusterOverviewCopy.refresh) {
                    Task { await refresh() }
                }
                .keyboardShortcut("r")
            }
        }
        .background {
            Button("Focus logs") {
                pane = .logs
                logsFocused = true
            }
            .keyboardShortcut("l")
            .hidden()
            .accessibilityHidden(true)
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private var statusPane: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Phase", value: detail.phase)
                LabeledContent("Ready", value: detail.ready ? "Ready" : "Not ready")
                if let node = detail.nodeName {
                    LabeledContent("Node", value: node)
                }
                Text(WorkloadsCopy.containers)
                    .font(.headline)
                    .padding(.top, 8)
                ForEach(detail.containers) { container in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(container.name)
                            .fontWeight(.semibold)
                        Text(container.image)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(
                            "\(container.ready ? "Ready" : "Not ready") · restarts \(container.restarts)"
                        )
                        .font(.caption)
                        ForEach(container.env) { env in
                            HStack {
                                Text(env.name)
                                Spacer()
                                Text(env.display)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Divider()
                Text(WorkloadsCopy.portForward)
                    .font(.headline)
                Text(WorkloadsCopy.bindLoopback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField(WorkloadsCopy.localPort, text: $localPort)
                        .frame(width: 90)
                    TextField(WorkloadsCopy.remotePort, text: $remotePort)
                        .frame(width: 90)
                    Button(WorkloadsCopy.portForward) {
                        TerminalLauncher.openPortForward(
                            namespace: namespace,
                            pod: name,
                            local: Int(localPort) ?? 18080,
                            remote: Int(remotePort) ?? 80
                        )
                    }
                    .disabled(!isRunning)
                }
            }
        } else {
            Text(WorkloadsCopy.empty)
                .foregroundStyle(.secondary)
        }
    }

    private var logsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let containers = detail?.containers, containers.count > 1 {
                Picker("Container", selection: $selectedContainer) {
                    ForEach(containers) { container in
                        Text(container.name).tag(Optional(container.name))
                    }
                }
                .onChange(of: selectedContainer) { _, _ in
                    Task { await refreshLogs() }
                }
            }
            ScrollView {
                Text(logs.isEmpty ? "—" : logs)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .focused($logsFocused)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var eventsPane: some View {
        Group {
            if let events = detail?.events, !events.isEmpty {
                List(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.type) · \(event.reason)")
                            .fontWeight(.semibold)
                        Text(event.message)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(WorkloadsCopy.noEvents)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isRunning: Bool {
        detail?.phase.compare("Running", options: .caseInsensitive) == .orderedSame
    }

    private func refresh() async {
        do {
            let loaded = try await client.pod(namespace: namespace, name: name)
            detail = loaded
            if selectedContainer == nil {
                selectedContainer = loaded.containers.first?.name
            }
            lastError = nil
            await refreshLogs()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshLogs() async {
        do {
            logs = try await client.podLogs(
                namespace: namespace,
                name: name,
                container: selectedContainer,
                tailLines: PodLogCap.maxLines
            )
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private enum PodDetailPane: String, Hashable {
    case status
    case logs
    case events
    case yaml
}
