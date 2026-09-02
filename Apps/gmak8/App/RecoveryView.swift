import AppKit
import Gmak8Kit
import Gmak8XPC
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct RecoveryView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @State private var includeCredentials = false
    @State private var lsofLines: [String] = []
    @State private var statusMessage: String?
    @State private var lsofTask: Task<Void, Never>?

    private var plan: RecoveryPlan {
        RecoveryPlan.make(
            status: session.status,
            extraError: RecoveryKind.settingsExtraError(settingsStore.lastError)
        )
    }

    var body: some View {
        Form {
            Section {
                Text(plan.title)
                    .font(.headline)
                Text(plan.message)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = plan.detail, detail != plan.message {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !lsofLines.isEmpty {
                Section("lsof") {
                    ForEach(lsofLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }
            }
            let collisions = session.status.publishedPorts.filter { $0.collision != .published }
            if !collisions.isEmpty {
                Section("Published ports") {
                    ForEach(Array(collisions.enumerated()), id: \.offset) { _, port in
                        Text("\(port.nodePort) in use (\(port.service) \(port.collision.rawValue))")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            Section("Recovery") {
                ForEach(plan.actions, id: \.self) { action in
                    Button(action.title) {
                        perform(action)
                    }
                    .disabled(!action.isAvailable)
                    .help(action.unavailableHelp ?? "")
                }
            }
            Section("Diagnostics") {
                Toggle("Include credentials", isOn: $includeCredentials)
                Button("Save Diagnostics Zip…") {
                    saveZip()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
        .padding()
        .onAppear {
            refreshLsof()
        }
        .onDisappear {
            lsofTask?.cancel()
        }
        .onChange(of: plan.kind) {
            refreshLsof()
        }
        .onChange(of: collidingNodePortsKey) {
            refreshLsof()
        }
    }

    private var collidingNodePortsKey: String {
        session.status.publishedPorts.filter { $0.collision == .collision }.map { String($0.nodePort) }.joined(
            separator: ","
        )
    }

    private func perform(_ action: RecoveryAction) {
        switch action {
        case .diagnosticsZip:
            saveZip()
        case .restartVM, .restartKubernetes:
            session.restartCluster()
        case .reset:
            appDelegate.confirmAndResetCluster()
        case .revealImages:
            reveal(HostPaths.current().dataImage, fallback: HostPaths.current().vmDirectory)
        case .pruneImages, .switchAPIPort16443, .pickAPIPort, .pickIngressHostPorts, .skipNodePort, .remapNodePort,
            .showK3sJournal:
            break
        case .showLsof:
            refreshLsof()
        case .showSerial:
            reveal(HostPaths.current().serialLog, fallback: HostPaths.current().vmDirectory)
        case .deleteCache:
            deleteAirgapCache()
        case .redownload:
            reveal(HostPaths.current().airgapCacheDirectory, fallback: HostPaths.current().caches)
        case .importFile:
            importAirgap()
        case .openLoginItems:
            SMAppService.openSystemSettingsLoginItems()
        case .switchToAPIOnly, .switchToKubernetes:
            appDelegate.openSettingsWindow()
        case .moveToApplications:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }

    private func refreshLsof() {
        let ports = HostPortLsof.probePorts(
            kind: plan.kind,
            collidingNodePorts: session.status.publishedPorts.filter { $0.collision == .collision }.map(\.nodePort)
        )
        lsofTask?.cancel()
        if ports.isEmpty {
            lsofLines = []
            return
        }
        lsofTask = Task {
            let lines = await Task.detached {
                HostPortLsof.occupancyLines(ports: ports)
            }.value
            guard !Task.isCancelled else {
                return
            }
            lsofLines = lines
        }
    }

    private func saveZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "gmak8-diagnostics.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let status = session.status
            let includeCredentials = includeCredentials
            Task {
                do {
                    let request = await Task.detached {
                        DiagnosticsArchive.collect(
                            paths: HostPaths.current(),
                            status: status,
                            includeCredentials: includeCredentials
                        )
                    }.value
                    try await Task.detached {
                        try DiagnosticsArchive.writeZip(
                            files: DiagnosticsArchive.files(from: request),
                            to: url,
                            ownerReadWrite: includeCredentials
                        )
                    }.value
                    statusMessage = "Saved \(url.lastPathComponent)"
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func importAirgap() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let paths = HostPaths.current()
            do {
                try FileManager.default.createDirectory(
                    at: paths.airgapCacheDirectory,
                    withIntermediateDirectories: true
                )
                let dest = paths.k3sAirgapFile
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: url, to: dest)
                statusMessage = "Imported \(url.lastPathComponent)"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func deleteAirgapCache() {
        let directory = HostPaths.current().airgapCacheDirectory
        do {
            if FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: directory)
            }
            statusMessage = "Airgap cache deleted"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reveal(_ url: URL, fallback: URL) {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        NSWorkspace.shared.open(fallback)
    }
}

@MainActor
enum ResetAlert {
    static func present(sheetWindow: NSWindow?, onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ResetConfirmation.messageText
        alert.informativeText = ResetConfirmation.informativeText
        alert.addButton(withTitle: ResetConfirmation.confirmTitle)
        alert.addButton(withTitle: ResetConfirmation.cancelTitle)
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            if ResetConfirmation.confirmed(response == .alertFirstButtonReturn) {
                onConfirm()
            }
        }
        if let window = sheetWindow {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }
}
