import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SetupSplitView()
            .onAppear {
                appDelegate.bindOpenWindow(openWindow)
            }
    }
}

struct ContentView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var assets = ClusterAssetSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("gmak8")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text(StatusText.displayName(session.status.state))
                    .foregroundStyle(.secondary)
                if let step = session.status.step {
                    Text(step)
                        .foregroundStyle(.secondary)
                }
                Text(StatusPresentation.productLine())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(StatusPresentation.nestedVirtLine(session.status.nestedVirt))
                    .font(.caption)
                if let error = session.connectionError {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .textSelection(.enabled)
                } else if let lastError = session.status.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                if let assetError = assets.lastError, !assetError.isEmpty {
                    Text(assetError)
                        .foregroundStyle(.red)
                        .font(.caption)
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
                    Button("Diagnostics") {
                        appDelegate.openRecoveryWindow()
                    }
                    Button("Reset…") {
                        appDelegate.confirmAndResetCluster()
                    }
                }
                Divider()
                ClusterAssetsView(assets: assets)
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            appDelegate.bindOpenWindow(openWindow)
            assets.refresh()
        }
    }
}
