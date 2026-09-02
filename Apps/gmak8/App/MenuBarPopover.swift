import Gmak8XPC
import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var session: ClusterSession

    var body: some View {
        let appearance = MenuBarIconAppearance(state: session.status.state)
        Image(systemName: appearance.systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint(for: appearance))
            .accessibilityLabel("gmak8 \(StatusText.displayName(session.status.state))")
    }

    private func tint(for appearance: MenuBarIconAppearance) -> Color {
        switch appearance {
        case .grayStopped:
            return .secondary
        case .blueStarting, .filledRunning:
            return .blue
        case .yellowDegraded:
            return .yellow
        case .redFailed:
            return .red
        case .paused:
            return .orange
        }
    }
}

struct MenuBarPopover: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(StatusPresentation.productLine())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(StatusPresentation.nestedVirtLine(session.status.nestedVirt))
                .font(.caption)
            Text(StatusPresentation.metricsLine(session.status.vm))
                .font(.caption)
                .monospacedDigit()
            if let banner = bannerText {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                if session.canStart {
                    Button("Start") {
                        session.startCluster()
                    }
                } else {
                    Button("Stop") {
                        session.stopCluster()
                    }
                    .disabled(!session.canStop)
                }
                Button("Pause") {}
                    .disabled(true)
                    .help("Pause is not available in v1.")
            }
            Button("Open gmak8") {
                appDelegate.openMainWindow(openWindow)
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("Open Terminal") {
                TerminalLauncher.open()
            }
            .keyboardShortcut("t", modifiers: .command)
            publishedPortsMenu
            Divider()
            Button("Settings…") {
                appDelegate.openSettingsWindow()
            }
            Button("Check for Updates…") {}
                .disabled(true)
                .help("Updates restart the cluster.")
            Button("Quit gmak8…") {
                appDelegate.requestQuit()
            }
        }
        .padding(12)
        .frame(minWidth: 280)
        .onAppear {
            appDelegate.bindOpenWindow(openWindow)
        }
    }

    private var header: some View {
        HStack {
            Text("gmak8")
                .font(.headline)
            Spacer()
            Text(StatusText.displayName(session.status.state))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var publishedPortsMenu: some View {
        let ports = session.status.publishedPorts
        Menu("Published ports (\(ports.count))") {
            if ports.isEmpty {
                Text("None")
            } else {
                ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                    Text(publishedPortLine(port))
                }
            }
        }
        .disabled(ports.isEmpty)
    }

    private var bannerText: String? {
        if let error = session.connectionError {
            return error.localizedDescription
        }
        if let lastError = session.status.lastError, !lastError.isEmpty {
            return lastError
        }
        if let step = session.status.step,
            session.status.state == .starting
                || session.status.state == .stopping
        {
            return step
        }
        return settingsStore.lastError
    }

    private func publishedPortLine(_ port: PublishedPort) -> String {
        var line = "\(port.service) \(port.hostURL)"
        if port.collision != .published {
            line += " (\(port.collision.rawValue))"
        }
        return line
    }
}
