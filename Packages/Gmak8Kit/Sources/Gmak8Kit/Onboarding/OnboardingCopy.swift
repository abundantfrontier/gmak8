import Foundation

public enum OnboardingCopy {
    public static let welcomeHeadline = "gmak8 runs Kubernetes on this Mac."
    public static let welcomeBody = "One local cluster, owned end-to-end on this Mac."

    public static let whatYouGetTitle = "What you get"
    public static let localCluster = "A local Kubernetes cluster on this Mac."
    public static let kubectlContext = "A kubectl context named gmak8."
    public static let menuBarExtra = "A menu bar extra for cluster status."
    public static let eurekaFootnote = "Eureka and KubeVirt are an optional profile."

    public static let assetsTitle = "Cluster assets"
    public static let assetsBody =
        "k3s needs container images to run Kubernetes (DNS, ingress, storage, metrics). gmak8 downloads those from GitHub. The guest disk is the Linux VM."
    public static let chooseFile = "Choose a file…"
    public static let download = "Download"
    public static let downloadThisPack = "Download Kubernetes images"
    public static let useLocalFile = "Use a file I already have…"
    public static let k3sAirgapHint =
        "These are container images k3s uses to run the cluster: DNS, ingress, storage, and metrics. gmak8 gets them from GitHub and checks the SHA-256."
    public static let downloadUnavailable =
        "Download is available when the pin is a GitHub release with a real SHA-256."
    public static let guestDigestUnpublished =
        "Guest download waits on a published gmak8 image. Use a local Linux .img or .raw for the VM disk."
    public static let guestLocalFileHint =
        "The VM disk is a Linux .img or .raw. Kubernetes images are a separate download."
    public static let offlineHint =
        "Choose a file… for a local archive. A sibling .sig is checked with Cosign when present."
    public static let sizeBudget500MiB = "≤ 500 MiB"

    public static let permissionsTitle = "Permissions"
    public static let unsupportedVirtualization =
        "This Mac cannot run a virtual machine (unsupported CPU, OS, or missing virtualization entitlement)."
    public static let nestedVirtAvailable = "Nested virtualization is available on this Mac."
    public static let nestedVirtUnavailable =
        "Nested virtualization is not available on this Mac (needs Apple Silicon M3 or later and macOS 15+). Kubernetes and Eureka API-only still work."
    public static let moveToApplications = "Move gmak8 to /Applications and re-open."
    public static let installToApplications = "Install to /Applications"
    public static let noFullDiskAccess = "gmak8 does not need Full Disk Access or Accessibility."
    public static let notificationsOptional = "Notifications are optional."

    public static let profileTitle = "Profile and resources"
    public static let eurekaExplanation =
        "This will not run the full GCE stack or stock env.py. u1.xlarge will Pending on this Mac. Use u1.nano/u1.medium and the airgapped aarch64 disk in docs/eureka-local.md. One nested VM + APIs + virtctl. HTTPS to the LoadBalancer IP is not available locally."
    public static let useEurekaAPIOnly = "Use Eureka API-only"
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
    public static let createAndStart = "Start cluster"
    public static let timeMachine = "VM disks are excluded from Time Machine. Reset is destructive."
    public static let continueTitle = "Continue"

    public static let setupTitle = "Setup"
    public static let getStartedSection = "Get started"
    public static let getStartedBody =
        "Kubernetes runs inside a Linux VM on this Mac, not natively on macOS. Container images (DNS, ingress, storage) are one download. The VM still needs a Linux disk."
    public static let stepFolder = "1. Files go in ~/gmak8."
    public static let stepK3s = "Download the container images k3s uses to run Kubernetes."
    public static let stepGuestWaiting =
        "Start needs a Linux disk for the VM. This Mac does not build that disk."
    public static let stepGuestReady = "Linux disk for the VM is ready."
    public static let guestHowToBuild =
        "On a Linux arm64 machine, from this repo:\n\ncd guest/mkosi\nmkosi\n\nCopy guest/mkosi/mkosi.output/os.img into ~/gmak8/guest/ then come back here."
    public static let stepStart = "Start the cluster."
    public static let linuxBooting = "Linux is booting. This can take a minute."
    public static let k3sImagesReady = "Kubernetes images are ready."
    public static let k3sImagesNeeded = "k3s needs container images for DNS, ingress, storage, and metrics."
    public static let guestRuntimeWaiting = "Waiting on a published guest image."
    public static let guestAdvancedFile = "I already have a Linux disk…"
    public static let folderSection = "Folder"
    public static let guestSection = "Linux disk"
    public static let k3sSection = "Images"
    public static let macSection = "Mac"
    public static let clusterSection = "Cluster"
    public static let folderBody =
        "Downloads and disks you add show up here. The running VM stays in Application Support."
    public static let chooseFolder = "Choose folder…"
    public static let revealInFinder = "Reveal in Finder"
    public static let openTerminal = "Open Terminal"
    public static let chooseMkosiRepo = "Choose the gmak8 repo (the folder that contains guest/mkosi)."
    public static let mkosiRepoMissing = "That folder has no guest/mkosi. Choose the gmak8 repo."
    public static let guestListEmpty = "No Linux VM disk in this folder yet."
    public static let k3sListEmpty = "Download Kubernetes images to continue."
    public static let useThis = "Use this"
    public static let inUse = "In use"
    public static let guestDownloadUnpublished =
        "Start needs a Linux disk built with mkosi on Linux. Copy os.img into ~/gmak8/guest/."

    public static var userFacingStrings: [String] {
        [
            welcomeHeadline,
            welcomeBody,
            whatYouGetTitle,
            localCluster,
            kubectlContext,
            menuBarExtra,
            eurekaFootnote,
            assetsTitle,
            assetsBody,
            chooseFile,
            download,
            downloadThisPack,
            useLocalFile,
            k3sAirgapHint,
            downloadUnavailable,
            guestDigestUnpublished,
            guestLocalFileHint,
            offlineHint,
            sizeBudget500MiB,
            permissionsTitle,
            unsupportedVirtualization,
            nestedVirtAvailable,
            nestedVirtUnavailable,
            moveToApplications,
            installToApplications,
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
            setupTitle,
            getStartedSection,
            getStartedBody,
            stepFolder,
            stepK3s,
            stepGuestWaiting,
            guestHowToBuild,
            stepGuestReady,
            stepStart,
            linuxBooting,
            k3sImagesReady,
            k3sImagesNeeded,
            guestRuntimeWaiting,
            guestAdvancedFile,
            folderSection,
            guestSection,
            k3sSection,
            macSection,
            clusterSection,
            folderBody,
            chooseFolder,
            revealInFinder,
            openTerminal,
            chooseMkosiRepo,
            mkosiRepoMissing,
            guestListEmpty,
            k3sListEmpty,
            useThis,
            inUse,
            guestDownloadUnpublished,
        ]
    }

    public static func userFacingAssetError(_ error: Error) -> String {
        switch error {
        case let signed as SignedAssetError:
            return signed.errorDescription ?? signed.localizedDescription
        case let guest as GuestOSDiskInstall.Failure:
            return guest.errorDescription ?? guest.localizedDescription
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
