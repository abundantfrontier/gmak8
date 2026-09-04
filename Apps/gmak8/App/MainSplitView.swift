import Gmak8Kit
import Gmak8Kubernetes
import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject private var session: ClusterSession
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appDelegate: Gmak8AppDelegate
    @StateObject private var overview: ClusterOverviewSession
    @State private var selection: ClusterSidebarItem? = .cluster

    init() {
        _overview = StateObject(wrappedValue: ClusterOverviewSession())
    }

    var body: some View {
        NavigationSplitView {
            List(visibleItems, selection: $selection) { item in
                Text(item.title).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 168, max: 220)
            .navigationTitle("gmak8")
        } detail: {
            switch selection ?? .cluster {
            case .cluster:
                ClusterOverviewView(overview: overview)
            case .workloads:
                emptyPane(ClusterOverviewCopy.workloads, ClusterOverviewCopy.workloadsEmpty)
            case .kubeVirt:
                emptyPane(ClusterOverviewCopy.kubeVirt, ClusterOverviewCopy.kubeVirtEmpty)
            case .images:
                emptyPane(ClusterOverviewCopy.images, ClusterOverviewCopy.imagesEmpty)
            case .diagnostics:
                RecoveryView()
            }
        }
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
                        selection = item
                    }
                }
                .keyboardShortcut(keyEquivalent(item), modifiers: .command)
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var visibleItems: [ClusterSidebarItem] {
        ClusterSidebarItem.visible(for: settingsStore.settings.profile)
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

    private func emptyPane(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(body)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(title)
    }
}
