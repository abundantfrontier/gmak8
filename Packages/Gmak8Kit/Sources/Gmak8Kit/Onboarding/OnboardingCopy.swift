import Foundation

public enum OnboardingCopy {
    public static let welcomeHeadline = "gmak8 runs Kubernetes on this Mac. Not Docker."
    public static let welcomeBody = "One local cluster, owned end-to-end on this Mac."

    public static let whatYouGetTitle = "What you get"
    public static let localCluster = "A local Kubernetes cluster on this Mac."
    public static let kubectlContext = "A kubectl context named gmak8."
    public static let menuBarExtra = "A menu bar extra for cluster status."
    public static let noDockerFootnote = "gmak8 is not Docker. There is no Docker Engine, Compose, or Docker socket."
    public static let eurekaFootnote = "Eureka and KubeVirt are an optional profile."

    public static let assetsTitle = "Cluster assets"
    public static let assetsBody =
        "Each file is verified with SHA-256 and keyful Cosign (public key pinned in the app)."
    public static let chooseFile = "Choose a file…"
    public static let download = "Download"
    public static let downloadUnavailable =
        "Remote download waits for a gmak8-signed GitHub Release (archive + .sig). Choose a file… for a local signed pair."
    public static let guestDigestUnpublished =
        "The guest disk SHA-256 is not published yet. Continue without it until a signed guest is available."
    public static let offlineHint = "Choose a file… next to its .sig."
    public static let sizeBudget500MiB = "≤ 500 MiB"

    public static let permissionsTitle = "Permissions"
    public static let unsupportedVirtualization =
        "This Mac cannot run a virtual machine (unsupported CPU, OS, or missing virtualization entitlement)."
    public static let nestedVirtAvailable = "Nested virtualization is available on this Mac."
    public static let nestedVirtUnavailable =
        "Nested virtualization is not available on this Mac (needs Apple Silicon M3 or later and macOS 15+). Kubernetes and Eureka API-only still work."
    public static let moveToApplications = "Move gmak8 to /Applications and re-open."
    public static let noFullDiskAccess = "gmak8 does not need Full Disk Access or Accessibility."
    public static let notificationsOptional = "Notifications are optional."

    public static let profileTitle = "Profile and resources"
    public static let eurekaExplanation =
        "This will not run the full GCE stack or stock env.py. u1.xlarge will Pending on this Mac. Use u1.nano/u1.medium and the airgapped aarch64 disk in docs/eureka-local.md. One nested VM + APIs + virtctl. HTTPS to the LoadBalancer IP is not available locally."
    public static let sparseDisk = "The data disk is sparse; it grows as you use it, up to the cap."

    public static let cliTitle = "CLI"
    public static let cliBody = "Install the gmak8 CLI into ~/.local/bin (no administrator password)."
    public static var pathExportSnippet: String { CLIPathInstaller.pathExportSnippet }
    public static let homebrewDetected =
        "Detected /opt/homebrew/bin. gmak8 still installs to ~/.local/bin and never requires admin."
    public static let virtctlSkipped = "virtctl is not in this app bundle yet; skipping that copy."
    public static let gmak8HelperMissing =
        "gmak8 CLI helper is missing from Contents/Helpers; skipping that copy."

    public static let createTitle = "Create cluster"
    public static let clusterName = "Cluster name"
    public static let kubernetesVersion = "Kubernetes version"
    public static var kubernetesVersionValue: String { K3sPin.displayVersion }
    public static let currentContextCheckbox = "Set gmak8 as kubectl current-context"
    public static let createAndStart = "Create and start"
    public static let timeMachine = "VM disks are excluded from Time Machine. Reset is destructive."
    public static let continueTitle = "Continue"

    public static var userFacingStrings: [String] {
        [
            welcomeHeadline,
            welcomeBody,
            whatYouGetTitle,
            localCluster,
            kubectlContext,
            menuBarExtra,
            noDockerFootnote,
            eurekaFootnote,
            assetsTitle,
            assetsBody,
            chooseFile,
            download,
            downloadUnavailable,
            guestDigestUnpublished,
            offlineHint,
            sizeBudget500MiB,
            permissionsTitle,
            unsupportedVirtualization,
            nestedVirtAvailable,
            nestedVirtUnavailable,
            moveToApplications,
            noFullDiskAccess,
            notificationsOptional,
            profileTitle,
            eurekaExplanation,
            sparseDisk,
            cliTitle,
            cliBody,
            pathExportSnippet,
            homebrewDetected,
            virtctlSkipped,
            gmak8HelperMissing,
            createTitle,
            clusterName,
            kubernetesVersion,
            kubernetesVersionValue,
            currentContextCheckbox,
            createAndStart,
            timeMachine,
            continueTitle,
        ]
    }

    public static func userFacingAssetError(_ error: Error) -> String {
        switch error {
        case let signed as SignedAssetError:
            return signed.errorDescription ?? signed.localizedDescription
        case AirgapError.missingArchive(let path):
            return "k3s airgap archive missing at \(path). Choose a file…"
        case AirgapError.missingSignature:
            return "k3s airgap Cosign signature missing"
        case AirgapError.sha256Mismatch:
            return "k3s airgap SHA-256 mismatch"
        case AirgapError.cosignVerifyFailed, AirgapError.invalidSignature:
            return "k3s airgap Cosign signature verify failed"
        case let airgap as AirgapError:
            return airgap.errorDescription ?? airgap.localizedDescription
        default:
            return error.localizedDescription
        }
    }

    public static func mentionsDockerHub(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("docker hub") || lower.contains("docker.io") || lower.contains("hub.docker.com")
    }
}
