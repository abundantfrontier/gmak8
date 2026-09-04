import Gmak8Kit
import Gmak8XPC
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var clusterSession: ClusterSession
    @StateObject private var onboarding = OnboardingSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("gmak8")
                .font(.largeTitle)
                .fontWeight(.semibold)
            pageContent
            if let error = onboarding.lastError ?? onboarding.assets.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            HStack {
                if onboarding.page != .welcome {
                    Button("Back") {
                        onboarding.back()
                    }
                    .disabled(onboarding.finishing)
                }
                Spacer()
                Button(onboarding.primaryTitle) {
                    if onboarding.page.isLast {
                        onboarding.finish(settingsStore: settingsStore, clusterSession: clusterSession)
                    } else {
                        onboarding.advance()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!onboarding.canAdvance || onboarding.finishing)
            }
        }
        .padding(32)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            onboarding.refreshCachedAssets()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch onboarding.page {
        case .welcome:
            welcomePage
        case .whatYouGet:
            whatYouGetPage
        case .assets:
            assetsPage
        case .permissions:
            permissionsPage
        case .profile:
            profilePage
        case .cli:
            cliPage
        case .createCluster:
            createPage
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.welcomeHeadline)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.welcomeBody)
                .foregroundStyle(.secondary)
        }
    }

    private var whatYouGetPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.whatYouGetTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.localCluster)
            Text(OnboardingCopy.kubectlContext)
            Text(OnboardingCopy.menuBarExtra)
            Text(OnboardingCopy.eurekaFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var assetsPage: some View {
        ClusterAssetsView(assets: onboarding.assets)
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.permissionsTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(PermissionsProbe.message(onboarding.permissions))
                .foregroundStyle(onboarding.permissions.canContinue ? Color.secondary : Color.red)
            if onboarding.showsInstallToApplications {
                Button(OnboardingCopy.installToApplications) {
                    onboarding.installToApplications()
                }
            }
            Text(CoreLaunchAgent.twoLoginItemsExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(OnboardingCopy.noFullDiskAccess)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(OnboardingCopy.notificationsOptional)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profilePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.profileTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Picker("Profile", selection: profileBinding) {
                ForEach(Profile.allCases, id: \.self) { profile in
                    Text(profile.displayName).tag(profile)
                }
            }
            .pickerStyle(.radioGroup)
            Text(
                "This Mac: \(onboarding.host.processorCount) CPU, \(onboarding.host.physicalMemoryGiB) GiB RAM, \(onboarding.host.freeDiskGiB) GiB free disk."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if onboarding.draft.profileIsAccepted {
                Stepper(value: cpuBinding, in: 1...max(1, onboarding.host.processorCount)) {
                    Text("vCPU \(onboarding.draft.cpu)")
                }
                Stepper(value: memoryBinding, in: 2...max(2, onboarding.host.physicalMemoryGiB)) {
                    Text("RAM \(onboarding.draft.memoryGiB) GiB")
                }
                Stepper(value: diskBinding, in: 20...1_024) {
                    Text("Disk \(onboarding.draft.dataDiskGiB) GiB")
                }
                Text(OnboardingCopy.sparseDisk)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if onboarding.draft.profile == .eureka || onboarding.draft.profile == .eurekaAPIOnly {
                Text(OnboardingCopy.eurekaExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let refusal = onboarding.draft.profileRefusal {
                Text(refusal.onboardingMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Use Eureka API-only") {
                    onboarding.applyProfile(.eurekaAPIOnly)
                }
            }
        }
    }

    private var cliPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.cliTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(OnboardingCopy.cliBody)
                .foregroundStyle(.secondary)
            Text(onboarding.cliPlan.destinationDirectory.path(percentEncoded: false))
                .font(.caption)
                .textSelection(.enabled)
            if onboarding.cliPlan.homebrewBinDetected {
                Text(OnboardingCopy.homebrewDetected)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if onboarding.cliPlan.pathExportNeeded {
                Text(OnboardingCopy.pathExportSnippet)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
            }
            if onboarding.cliPlan.skippedVirtctl {
                Text(OnboardingCopy.virtctlSkipped)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if onboarding.cliPlan.missingGmak8Helper {
                Text(OnboardingCopy.gmak8HelperMissing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var createPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.createTitle)
                .font(.title2)
                .fontWeight(.semibold)
            HStack {
                Text(OnboardingCopy.clusterName)
                TextField(OnboardingCopy.clusterName, text: clusterNameBinding)
            }
            HStack {
                Text(OnboardingCopy.kubernetesVersion)
                Text(OnboardingCopy.kubernetesVersionValue)
                    .foregroundStyle(.secondary)
            }
            Toggle(
                OnboardingCopy.currentContextCheckbox,
                isOn: currentContextBinding
            )
            Text(OnboardingCopy.timeMachine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var profileBinding: Binding<Profile> {
        Binding(
            get: { onboarding.draft.profile },
            set: { onboarding.applyProfile($0) }
        )
    }

    private var clusterNameBinding: Binding<String> {
        Binding(
            get: { onboarding.draft.clusterName },
            set: { onboarding.draft.clusterName = $0 }
        )
    }

    private var currentContextBinding: Binding<Bool> {
        Binding(
            get: { onboarding.draft.setCurrentContextOnStart },
            set: { onboarding.draft.setCurrentContextOnStart = $0 }
        )
    }

    private var cpuBinding: Binding<Int> {
        Binding(
            get: { onboarding.draft.cpu },
            set: { onboarding.draft.cpu = $0 }
        )
    }

    private var memoryBinding: Binding<Int> {
        Binding(
            get: { onboarding.draft.memoryGiB },
            set: { onboarding.draft.memoryGiB = $0 }
        )
    }

    private var diskBinding: Binding<Int> {
        Binding(
            get: { onboarding.draft.dataDiskGiB },
            set: { onboarding.draft.dataDiskGiB = $0 }
        )
    }

}
