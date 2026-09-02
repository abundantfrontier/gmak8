import Foundation

public enum RecoveryKind: String, Equatable, Sendable, CaseIterable {
    case none
    case vmPanic
    case diskFull
    case apiPortConflict
    case ingressPortConflict
    case nodePortCollision
    case kubernetesNotReady
    case guestAirgapVerifyFailed
    case agentTimeout
    case sqliteCorrupt
    case hypervisorPressure
    case diskImagesLocked
    case loginItemDenied
    case nestedVirtUnavailable
    case translocatedApp
}

public enum RecoveryAction: String, Equatable, Sendable, CaseIterable {
    case diagnosticsZip
    case restartVM
    case reset
    case revealImages
    case pruneImages
    case switchAPIPort16443
    case pickAPIPort
    case showLsof
    case pickIngressHostPorts
    case skipNodePort
    case remapNodePort
    case showK3sJournal
    case restartKubernetes
    case deleteCache
    case redownload
    case importFile
    case showSerial
    case openLoginItems
    case switchToAPIOnly
    case switchToKubernetes
    case moveToApplications

    public var title: String {
        switch self {
        case .diagnosticsZip:
            return "Save Diagnostics Zip…"
        case .restartVM:
            return "Restart VM"
        case .reset:
            return "Reset…"
        case .revealImages:
            return "Reveal Images"
        case .pruneImages:
            return "Prune Images"
        case .switchAPIPort16443:
            return "Switch to 16443"
        case .pickAPIPort:
            return "Pick a Port"
        case .showLsof:
            return "Show lsof"
        case .pickIngressHostPorts:
            return "Pick Alternate Host Ports"
        case .skipNodePort:
            return "Skip This Port"
        case .remapNodePort:
            return "Remap Port"
        case .showK3sJournal:
            return "k3s Journal"
        case .restartKubernetes:
            return "Restart Kubernetes"
        case .deleteCache:
            return "Delete Cache"
        case .redownload:
            return "Re-download"
        case .importFile:
            return "Import File…"
        case .showSerial:
            return "Serial Log"
        case .openLoginItems:
            return "Open Login Items"
        case .switchToAPIOnly:
            return "Switch to API-only"
        case .switchToKubernetes:
            return "Switch to Kubernetes"
        case .moveToApplications:
            return "Move to /Applications"
        }
    }

    public var isAvailable: Bool {
        unavailableHelp == nil
    }

    public var unavailableHelp: String? {
        switch self {
        case .pruneImages:
            return "Image prune is not available yet."
        case .switchAPIPort16443, .pickAPIPort:
            return "gmak8 already tries 16443 when 6443 is in use. Host port picking is not available yet."
        case .pickIngressHostPorts:
            return "Alternate host ports are not configurable yet. Traefik stays on guest 80/443."
        case .skipNodePort, .remapNodePort:
            return "NodePort skip/remap is listed on published ports; changing publishes is not available yet."
        case .showK3sJournal:
            return "k3s journal is in the guest. Use Serial Log on the host."
        default:
            return nil
        }
    }
}

public enum RecoveryCopy {
    public static let diskImagesLocked = "Another gmak8 (engine.sock live) holds data.img. Quit that instance."
    public static let translocated = "Move gmak8 to /Applications and re-open."
    public static let sqliteCorrupt =
        "The cluster database is corrupt. Time Machine excludes vm/. Reset is the only recovery; there is no snapshot."
    public static let hypervisorPressure = "Another VM may be using CPU/RAM."
    public static let loginItemDenied =
        "Open System Settings → Login Items. gmak8 uses two Login Items: (1) gmak8-core LaunchAgent, which owns the background cluster, and (2) the gmak8 menu extra, which shows status at login."
    public static let nestedVirtUnavailable =
        "This Mac cannot run nested VMs. Switch to the Eureka API-only or Kubernetes profile."
    public static let unsupportedHardware =
        "This Mac cannot run a virtual machine (unsupported CPU, OS, or missing virtualization entitlement)."
    public static let noSnapshot = "There is no snapshot. Time Machine excludes vm/. Reset is destructive."
    public static let apiPortHint = "gmak8 tries 16443 when 6443 is in use. Traefik stays on guest 80/443."
    public static let ingressPortHint = "Pick alternate host ports. Traefik in the guest stays on 80/443."
    public static let diskFullHint = "Reveal or prune images. Disk resize is not available."
}

public enum ResetConfirmation {
    public static let messageText = "Reset cluster?"
    public static let informativeText =
        "Reset deletes the VM disks. Time Machine excludes vm/. There is no snapshot. This cannot be undone."
    public static let confirmTitle = "Reset"
    public static let cancelTitle = "Cancel"
    public static let engineRequest = EngineRequest.reset(force: true)

    public static func confirmed(_ firstButton: Bool) -> Bool {
        firstButton
    }
}

public enum RecoveryPorts {
    public static let api = 6443
    public static let apiFallback = 16_443
    public static let http = 8080
    public static let httpFallback = 18_080
    public static let https = 8443
    public static let httpsFallback = 18_443
}

public struct RecoveryPlan: Equatable, Sendable {
    public var kind: RecoveryKind
    public var title: String
    public var message: String
    public var actions: [RecoveryAction]
    public var detail: String?

    public init(
        kind: RecoveryKind,
        title: String,
        message: String,
        actions: [RecoveryAction],
        detail: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions
        self.detail = detail
    }

    public static func make(status: EngineStatus, extraError: String? = nil) -> RecoveryPlan {
        let kind = RecoveryKind.classify(status: status, extraError: extraError)
        let raw = RecoveryKind.rawError(status: status, extraError: extraError)
        return plan(kind: kind, rawError: raw, status: status)
    }

    private static func plan(kind: RecoveryKind, rawError: String, status: EngineStatus) -> RecoveryPlan {
        switch kind {
        case .none:
            return RecoveryPlan(
                kind: .none,
                title: "Diagnostics",
                message: "Save a diagnostics zip for support.",
                actions: [.diagnosticsZip]
            )
        case .vmPanic:
            return RecoveryPlan(
                kind: .vmPanic,
                title: "VM panic",
                message: rawError.isEmpty ? "The virtual machine stopped unexpectedly." : rawError,
                actions: [.diagnosticsZip, .restartVM, .reset]
            )
        case .diskFull:
            return RecoveryPlan(
                kind: .diskFull,
                title: "Disk full",
                message: RecoveryCopy.diskFullHint,
                actions: [.revealImages, .pruneImages],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .apiPortConflict:
            return RecoveryPlan(
                kind: .apiPortConflict,
                title: "API port conflict",
                message: RecoveryCopy.apiPortHint,
                actions: [.switchAPIPort16443, .pickAPIPort, .showLsof],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .ingressPortConflict:
            return RecoveryPlan(
                kind: .ingressPortConflict,
                title: "8080 / 8443 conflict",
                message: RecoveryCopy.ingressPortHint,
                actions: [.pickIngressHostPorts, .showLsof],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .nodePortCollision:
            return RecoveryPlan(
                kind: .nodePortCollision,
                title: "NodePort collision",
                message: nodePortMessage(status: status, rawError: rawError),
                actions: [.skipNodePort, .remapNodePort, .showLsof],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .kubernetesNotReady:
            return RecoveryPlan(
                kind: .kubernetesNotReady,
                title: "Kubernetes not ready",
                message: rawError.isEmpty ? "Kubernetes did not become ready." : rawError,
                actions: [.showK3sJournal, .showSerial, .restartKubernetes, .reset]
            )
        case .guestAirgapVerifyFailed:
            return RecoveryPlan(
                kind: .guestAirgapVerifyFailed,
                title: "Guest image verify failed",
                message: rawError.isEmpty ? "The guest or airgap archive failed verification." : rawError,
                actions: [.deleteCache, .redownload, .importFile]
            )
        case .agentTimeout:
            return RecoveryPlan(
                kind: .agentTimeout,
                title: "Guest agent timeout",
                message: rawError.isEmpty ? "Timed out waiting for the guest agent." : rawError,
                actions: [.restartVM, .showSerial]
            )
        case .sqliteCorrupt:
            return RecoveryPlan(
                kind: .sqliteCorrupt,
                title: "Cluster database corrupt",
                message: RecoveryCopy.sqliteCorrupt,
                actions: [.reset],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .hypervisorPressure:
            return RecoveryPlan(
                kind: .hypervisorPressure,
                title: "Hypervisor pressure",
                message: RecoveryCopy.hypervisorPressure,
                actions: [.diagnosticsZip],
                detail: rawError.isEmpty ? nil : rawError
            )
        case .diskImagesLocked:
            return RecoveryPlan(
                kind: .diskImagesLocked,
                title: "Disk images locked",
                message: RecoveryCopy.diskImagesLocked,
                actions: []
            )
        case .loginItemDenied:
            return RecoveryPlan(
                kind: .loginItemDenied,
                title: "Login item denied",
                message: RecoveryCopy.loginItemDenied,
                actions: [.openLoginItems]
            )
        case .nestedVirtUnavailable:
            return RecoveryPlan(
                kind: .nestedVirtUnavailable,
                title: "Nested virt unavailable",
                message: RecoveryCopy.nestedVirtUnavailable,
                actions: [.switchToAPIOnly, .switchToKubernetes]
            )
        case .translocatedApp:
            return RecoveryPlan(
                kind: .translocatedApp,
                title: "Move gmak8 to /Applications",
                message: RecoveryCopy.translocated,
                actions: [.moveToApplications]
            )
        }
    }

    private static func nodePortMessage(status: EngineStatus, rawError: String) -> String {
        let collisions = status.publishedPorts.filter { $0.collision == .collision }
        if collisions.isEmpty {
            return rawError.isEmpty ? "A NodePort is in use on the host." : rawError
        }
        let lines = collisions.map { port in
            "\(port.nodePort) in use (\(port.service))"
        }
        return lines.joined(separator: "\n")
    }
}

extension RecoveryKind {
    /// Settings/login copy only. Connection errors and persist I/O must not become VM panic.
    public static func settingsExtraError(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        switch classify(lastError: trimmed) {
        case .translocatedApp, .loginItemDenied:
            return trimmed
        default:
            return nil
        }
    }

    public static func classify(status: EngineStatus, extraError: String? = nil) -> RecoveryKind {
        let last = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !last.isEmpty {
            return classify(text: last, status: status)
        }
        if status.publishedPorts.contains(where: { $0.collision == .collision }) {
            return .nodePortCollision
        }
        let extra = extraError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if extra.isEmpty {
            return .none
        }
        switch classify(text: extra, status: status) {
        case .translocatedApp:
            return .translocatedApp
        case .loginItemDenied:
            return .loginItemDenied
        default:
            return .none
        }
    }

    public static func classify(lastError: String?, publishedPorts: [PublishedPort] = [], step: String? = nil)
        -> RecoveryKind
    {
        classify(
            status: EngineStatus(state: .failed, step: step, lastError: lastError, publishedPorts: publishedPorts)
        )
    }

    static func rawError(status: EngineStatus, extraError: String?) -> String {
        let last = status.lastError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !last.isEmpty {
            return last
        }
        return extraError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func classify(text: String, status: EngineStatus) -> RecoveryKind {
        let lower = text.lowercased()
        if lower.contains("move gmak8 to /applications") || lower.contains("apptranslocation") {
            return .translocatedApp
        }
        if lower.contains("holds data.img") || lower.contains("disk images locked")
            || (lower.contains("engine.sock") && lower.contains("data.img"))
        {
            return .diskImagesLocked
        }
        if isSQLiteCorrupt(lower) {
            return .sqliteCorrupt
        }
        if lower.contains("login item") {
            return .loginItemDenied
        }
        if lower.contains("nested virt") || lower.contains("nested virtualization")
            || lower.contains("nested vm")
        {
            return .nestedVirtUnavailable
        }
        if lower.contains("another vm may be using cpu/ram") {
            return .hypervisorPressure
        }
        if isDiskFull(lower) {
            return .diskFull
        }
        if isAddressInUse(lower) {
            if mentionsPort(text, RecoveryPorts.api) || mentionsPort(text, RecoveryPorts.apiFallback) {
                return .apiPortConflict
            }
            if mentionsPort(text, RecoveryPorts.http) || mentionsPort(text, RecoveryPorts.https)
                || mentionsPort(text, RecoveryPorts.httpFallback) || mentionsPort(text, RecoveryPorts.httpsFallback)
            {
                return .ingressPortConflict
            }
            if lower.contains("in use by pid") {
                return .nodePortCollision
            }
        }
        if status.publishedPorts.contains(where: { $0.collision == .collision }) {
            return .nodePortCollision
        }
        if isAirgapFailure(lower) {
            return .guestAirgapVerifyFailed
        }
        if lower.contains("timed out waiting for") {
            if lower.contains("guestagent") || lower.contains("datadisk") {
                return .agentTimeout
            }
            if lower.contains("airgap") {
                return .guestAirgapVerifyFailed
            }
            return .kubernetesNotReady
        }
        if lower.contains("on-disk k3s") || lower.contains("node ready") || lower.contains("kubernetes not ready") {
            return .kubernetesNotReady
        }
        return .vmPanic
    }

    private static func isSQLiteCorrupt(_ lower: String) -> Bool {
        if lower.contains("database disk image is malformed") || lower.contains("sqlite_corrupt")
            || lower.contains("malformed database")
        {
            return true
        }
        guard lower.contains("sqlite") else {
            return false
        }
        return lower.contains("corrupt") || lower.contains("malformed")
    }

    private static func isDiskFull(_ lower: String) -> Bool {
        lower.contains("no space") || lower.contains("disk full") || lower.contains("not enough space")
            || lower.contains("insufficient disk") || lower.contains("20%") || lower.contains("bytes free")
    }

    private static func isAddressInUse(_ lower: String) -> Bool {
        lower.contains("already in use") || lower.contains("in use") || lower.contains("bind:")
    }

    private static func isAirgapFailure(_ lower: String) -> Bool {
        lower.contains("cosign") || lower.contains("airgap") || lower.contains("sha-256")
            || lower.contains("sha256") || lower.contains("docker.io/rancher") || lower.contains("verify failed")
    }

    private static func mentionsPort(_ text: String, _ port: Int) -> Bool {
        let pattern = "(?<![0-9])\(port)(?![0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
