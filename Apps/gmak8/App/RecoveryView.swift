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

    var body: some View {
        let plan = RecoveryPlan.make(
            status: session.status,
            extraError: settingsStore.lastError ?? session.connectionError?.localizedDescription
        )
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
                        perform(action, plan: plan)
                    }
                    .disabled(action == .pruneImages)
                    .help(action == .pruneImages ? "Image prune is not available yet." : "")
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
            refreshLsof(for: plan.kind)
        }
    }

    private func perform(_ action: RecoveryAction, plan: RecoveryPlan) {
        switch action {
        case .diagnosticsZip:
            saveZip()
        case .restartVM, .restartKubernetes:
            session.restartCluster()
        case .reset:
            appDelegate.confirmAndResetCluster()
        case .revealImages:
            reveal(HostPaths.current().dataImage, fallback: HostPaths.current().vmDirectory)
        case .pruneImages:
            break
        case .switchAPIPort16443, .pickAPIPort, .showLsof, .pickIngressHostPorts, .skipNodePort, .remapNodePort:
            refreshLsof(for: plan.kind)
        case .showK3sJournal, .showSerial:
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

    private func refreshLsof(for kind: RecoveryKind) {
        var ports: [Int] = []
        switch kind {
        case .apiPortConflict:
            ports = [RecoveryPorts.api, RecoveryPorts.apiFallback]
        case .ingressPortConflict:
            ports = [RecoveryPorts.http, RecoveryPorts.https]
        case .nodePortCollision:
            ports = session.status.publishedPorts.filter { $0.collision == .collision }.map(\.nodePort)
        default:
            ports = []
        }
        var lines: [String] = []
        for port in ports {
            let occupants = (try? HostPortLsof.occupants(port: port)) ?? []
            lines.append(HostPortLsof.occupancyLine(port: port, occupants: occupants))
        }
        lsofLines = lines
    }

    private func saveZip() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "gmak8-diagnostics.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let request = DiagnosticsArchive.collect(
                paths: HostPaths.current(),
                status: session.status,
                includeCredentials: includeCredentials
            )
            do {
                try DiagnosticsArchive.writeZip(files: DiagnosticsArchive.files(from: request), to: url)
                statusMessage = "Saved \(url.lastPathComponent)"
            } catch {
                statusMessage = error.localizedDescription
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
    static func present(onConfirm: @escaping () -> Void) {
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
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.level != .statusBar }) {
            alert.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(alert.runModal())
        }
    }
}
