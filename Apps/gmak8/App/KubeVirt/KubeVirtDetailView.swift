import Gmak8Kubernetes
import SwiftUI

struct KubeVirtDetailView: View {
    let kind: KubeVirtKind
    let namespace: String
    let name: String
    let client: any KubeVirtClient
    var nestedVirt: Bool
    var kvmPresent: Bool?
    var onDiagnostics: () -> Void

    @State private var detail: KubeVirtDetail?
    @State private var pane = KubeVirtDetailPane.status
    @State private var lastError: String?
    @State private var isMutating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = lastError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Picker("Pane", selection: $pane) {
                Text(WorkloadsCopy.status).tag(KubeVirtDetailPane.status)
                Text(WorkloadsCopy.events).tag(KubeVirtDetailPane.events)
                Text(WorkloadsCopy.yaml).tag(KubeVirtDetailPane.yaml)
            }
            .pickerStyle(.segmented)
            switch pane {
            case .status:
                statusPane
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
        .navigationTitle(name)
        .toolbar {
            ToolbarItemGroup {
                if kind == .virtualMachine {
                    Button(KubeVirtCopy.start) {
                        Task { await setRunning(true) }
                    }
                    .disabled(isMutating || detail?.running == true)
                    Button(KubeVirtCopy.stop) {
                        Task { await setRunning(false) }
                    }
                    .disabled(isMutating || detail?.running == false)
                }
                Button(ClusterOverviewCopy.refresh) {
                    Task { await refresh() }
                }
                .keyboardShortcut("r")
            }
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private var statusPane: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 10) {
                if showsPendingCopy(detail) {
                    Text(KubeVirtCopy.nestedVirtUnsupported)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button(KubeVirtCopy.diagnostics, action: onDiagnostics)
                }
                LabeledContent("Phase", value: detail.phase)
                LabeledContent("Ready", value: detail.ready ? "Ready" : "Not ready")
                if let running = detail.running {
                    LabeledContent(KubeVirtCopy.running, value: running ? "Yes" : "No")
                }
                if let instancetype = detail.instancetype, !instancetype.isEmpty {
                    LabeledContent(KubeVirtCopy.instancetype, value: instancetype)
                }
                if !detail.dataVolumes.isEmpty {
                    LabeledContent(KubeVirtCopy.dataVolumes, value: detail.dataVolumes.joined(separator: ", "))
                }
                Text(KubeVirtCopy.conditions)
                    .font(.headline)
                    .padding(.top, 8)
                if detail.conditions.isEmpty {
                    Text(KubeVirtCopy.noConditions)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.conditions) { condition in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(condition.type) · \(condition.status)")
                                .fontWeight(.semibold)
                            if !condition.reason.isEmpty || !condition.message.isEmpty {
                                Text(
                                    [condition.reason, condition.message].filter { !$0.isEmpty }.joined(
                                        separator: " — ")
                                )
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            Text(KubeVirtCopy.empty)
                .foregroundStyle(.secondary)
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

    private func showsPendingCopy(_ detail: KubeVirtDetail) -> Bool {
        if detail.pendingUnschedulable {
            return true
        }
        if !nestedVirt || kvmPresent == false {
            return detail.kind == .virtualMachineInstance && detail.phase == "Pending"
        }
        return false
    }

    private func refresh() async {
        do {
            detail = try await client.detail(kind: kind, namespace: namespace, name: name)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func setRunning(_ running: Bool) async {
        isMutating = true
        defer { isMutating = false }
        do {
            detail = try await client.setRunning(namespace: namespace, name: name, running: running)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private enum KubeVirtDetailPane: String, Hashable {
    case status
    case events
    case yaml
}
