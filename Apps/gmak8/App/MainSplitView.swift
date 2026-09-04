import Gmak8Kit
import Gmak8Kubernetes
import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @StateObject private var overview: ClusterOverviewSession
    @State private var selection: ClusterSidebarItem? = .cluster
    @State private var sidebarReselectEpoch = 0

    init() {
        _overview = StateObject(wrappedValue: ClusterOverviewSession())
    }

    var body: some View {
        NavigationSplitView {
            List(visibleItems, selection: $selection) { item in
                Button(item.title) {
                    activate(item)
                }
                .buttonStyle(.plain)
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 168, max: 220)
            .navigationTitle("gmak8")
        } detail: {
            switch selection ?? .cluster {
            case .cluster:
                ClusterOverviewView(overview: overview)
            case .workloads:
                WorkloadsView()
            case .kubeVirt:
                KubeVirtView()
            case .images:
                ImagesView()
            case .diagnostics:
                RecoveryView()
            }
        }
        .environment(\.sidebarReselectEpoch, sidebarReselectEpoch)
        .background(shortcutButtons)
        .onAppear {
            overview.includeEureka = settingsStore.settings.profile != .kubernetes
            overview.startPolling()
        }
        .onDisappear {
            overview.stopPolling()
        }
        .onChange(of: settingsStore.settings.profile) { _, profile in
            overview.includeEureka = profile != .kubernetes
            Task { await overview.refresh() }
        }
    }

    private var shortcutButtons: some View {
        Group {
            ForEach(ClusterSidebarItem.allCases) { item in
                Button(item.title) {
                    if visibleItems.contains(item) {
                        activate(item)
                    }
                }
                .keyboardShortcut(keyEquivalent(item), modifiers: .command)
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var visibleItems: [ClusterSidebarItem] {
        ClusterSidebarItem.visible(
            for: settingsStore.settings.profile,
            kubeVirtEnabled: settingsStore.settings.kubeVirtEnabled
        )
    }

    private func activate(_ item: ClusterSidebarItem) {
        if selection == item {
            sidebarReselectEpoch += 1
        }
        selection = item
    }

    private func keyEquivalent(_ item: ClusterSidebarItem) -> KeyEquivalent {
        switch item {
        case .cluster: "1"
        case .workloads: "2"
        case .kubeVirt: "3"
        case .images: "4"
        case .diagnostics: "5"
        }
    }

}

private struct SidebarReselectEpochKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var sidebarReselectEpoch: Int {
        get { self[SidebarReselectEpochKey.self] }
        set { self[SidebarReselectEpochKey.self] = newValue }
    }
}
