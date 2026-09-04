import Foundation

/// 0.9/1.0 VZ soak contract. Live execution is self-hosted `gmak8-vm` only — never GitHub-hosted macOS.
public enum SoakStep: String, Sendable, Equatable, CaseIterable {
    case startStop
    case dirtyKillFsck
    case loadImage
    case nginxNodePortCurl
    case pvcUnderMntData
    case u1NanoClusterInstancetype
    case aarch64VMIReady
    case saVirtiofs
    case virtctlPortForwardStdio
}

public enum SoakPlanError: Error, Equatable, Sendable {
    case nonLoopbackHost(String)
    case invalidPort(Int)
}

public enum SoakPlan {
    public static let runnerLabel = "gmak8-vm"
    public static let runnerLabels = ["self-hosted", runnerLabel]
    public static let scriptFile = "scripts/soak.sh"
    public static let defaultCycles = 50
    public static let gate09 = "0.9"
    public static let gate10 = "1.0"
    public static let nodePortHost = "127.0.0.1"
    public static let forbiddenBindHost = "0.0.0.0"
    public static let guestOverlayIPv4 = "192.168.127.2"
    public static let coreProcessName = "gmak8-core"
    public static let launchAgentLabel = "dev.gmak8.core"
    public static let cliHelperName = "gmak8"
    public static let helpersDirectory = "Contents/Helpers"
    public static let diskAttachment = "nvme"
    public static let diskCachingMode = "cached"
    public static let diskSynchronizationMode = "full"
    public static let forbiddenDiskAttachment = "virtio-blk"
    public static let lockSuffix = ".lock"
    public static let fsckTarget = "data.img"
    public static let fsckFlag = "-n"
    public static let neverUnlinkLockFiles = true
    public static let dockerHubAllowed = false
    public static let virtctlLiveEnabled = false
    public static let imageLoadSkipReason = "no airgap workload blob; refusing Docker Hub pull"
    public static let virtctlDeferredReason = "virtctl --stdio soak waits for a Ready VMI (PRs 27-28)"
    public static let githubHostedMacImages = ["macos-15", "macos-14", "macos-latest"]

    public static let steps09: [SoakStep] = [
        .startStop,
        .dirtyKillFsck,
        .loadImage,
        .nginxNodePortCurl,
    ]

    public static let steps10Only: [SoakStep] = [
        .pvcUnderMntData,
        .u1NanoClusterInstancetype,
        .aarch64VMIReady,
        .saVirtiofs,
        .virtctlPortForwardStdio,
    ]

    public static func parseCycles(_ raw: String?) -> Int? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return defaultCycles
        }
        guard let value = Int(text), value > 0 else {
            return nil
        }
        return value
    }

    public static func parseGate(_ raw: String?) -> String? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return gate09
        }
        if text == gate09 || text == gate10 {
            return text
        }
        return nil
    }

    public static func steps(gate: String) -> [SoakStep] {
        switch gate {
        case gate09:
            return steps09
        case gate10:
            return steps09 + steps10Only
        default:
            return []
        }
    }

    public static func includesVirtctl(gate: String) -> Bool {
        steps(gate: gate).contains(.virtctlPortForwardStdio)
    }

    public static func allowsVirtctlLive(gate: String) -> Bool {
        includesVirtctl(gate: gate) && virtctlLiveEnabled
    }

    public static func nodePortURL(port: Int, host: String = nodePortHost, scheme: String = "http") throws
        -> String
    {
        guard host == nodePortHost else {
            throw SoakPlanError.nonLoopbackHost(host)
        }
        guard port > 0, port <= 65_535 else {
            throw SoakPlanError.invalidPort(port)
        }
        return "\(scheme)://\(host):\(port)"
    }

    public static func joinedSteps(gate: String) -> String {
        steps(gate: gate).map(\.rawValue).joined(separator: ",")
    }
}
