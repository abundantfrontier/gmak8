import Foundation
import Testing

@testable import Gmak8Kit

struct SoakPlanTests {
    @Test func defaultCyclesAndGates() {
        #expect(SoakPlan.defaultCycles == 50)
        #expect(SoakPlan.parseCycles(nil) == 50)
        #expect(SoakPlan.parseCycles("") == 50)
        #expect(SoakPlan.parseCycles(" 50 ") == 50)
        #expect(SoakPlan.parseCycles("1") == 1)
        #expect(SoakPlan.parseCycles("0") == nil)
        #expect(SoakPlan.parseCycles("-1") == nil)
        #expect(SoakPlan.parseCycles("abc") == nil)
        #expect(SoakPlan.parseGate(nil) == SoakPlan.gate09)
        #expect(SoakPlan.parseGate("") == SoakPlan.gate09)
        #expect(SoakPlan.parseGate("0.9") == SoakPlan.gate09)
        #expect(SoakPlan.parseGate("1.0") == SoakPlan.gate10)
        #expect(SoakPlan.parseGate("2.0") == nil)
    }

    @Test func steps09ExcludeVirtctlAndDockerHub() {
        #expect(
            SoakPlan.steps09.map(\.rawValue) == [
                "startStop",
                "dirtyKillFsck",
                "loadImage",
                "nginxNodePortCurl",
            ])
        #expect(!SoakPlan.steps09.contains(.virtctlPortForwardStdio))
        #expect(!SoakPlan.includesVirtctl(gate: SoakPlan.gate09))
        #expect(!SoakPlan.allowsVirtctlLive(gate: SoakPlan.gate09))
        #expect(!SoakPlan.allowsVirtctlLive(gate: SoakPlan.gate10))
        #expect(!SoakPlan.dockerHubAllowed)
        #expect(!SoakPlan.virtctlLiveEnabled)
        #expect(SoakPlan.imageLoadSkipReason.contains("Docker Hub"))
        #expect(SoakPlan.virtctlDeferredReason.contains("25-28"))
        #expect(
            SoakPlan.joinedSteps(gate: SoakPlan.gate09)
                == "startStop,dirtyKillFsck,loadImage,nginxNodePortCurl"
        )
    }

    @Test func steps10AddKubeVirtGates() {
        let steps = SoakPlan.steps(gate: SoakPlan.gate10)
        #expect(SoakPlan.steps09.allSatisfy { steps.contains($0) })
        #expect(steps.contains(.pvcUnderMntData))
        #expect(steps.contains(.u1NanoClusterInstancetype))
        #expect(steps.contains(.aarch64VMIReady))
        #expect(steps.contains(.saVirtiofs))
        #expect(steps.contains(.virtctlPortForwardStdio))
        #expect(SoakPlan.includesVirtctl(gate: SoakPlan.gate10))
        #expect(SoakPlan.steps(gate: "nope").isEmpty)
    }

    @Test func nodePortCurlIsLoopbackOnly() throws {
        #expect(SoakPlan.nodePortHost == "127.0.0.1")
        #expect(try SoakPlan.nodePortURL(port: 30_080) == "http://127.0.0.1:30080")
        #expect(try SoakPlan.nodePortURL(port: 30_080, scheme: "https") == "https://127.0.0.1:30080")
        #expect(throws: SoakPlanError.nonLoopbackHost(SoakPlan.forbiddenBindHost)) {
            try SoakPlan.nodePortURL(port: 30_080, host: SoakPlan.forbiddenBindHost)
        }
        #expect(throws: SoakPlanError.nonLoopbackHost(SoakPlan.guestOverlayIPv4)) {
            try SoakPlan.nodePortURL(port: 30_080, host: SoakPlan.guestOverlayIPv4)
        }
        #expect(throws: SoakPlanError.invalidPort(0)) {
            try SoakPlan.nodePortURL(port: 0)
        }
    }

    @Test func diskContractIsNVMeCachedFull() {
        #expect(SoakPlan.diskAttachment == "nvme")
        #expect(SoakPlan.diskCachingMode == "cached")
        #expect(SoakPlan.diskSynchronizationMode == "full")
        #expect(SoakPlan.forbiddenDiskAttachment == "virtio-blk")
        #expect(SoakPlan.neverUnlinkLockFiles)
        #expect(SoakPlan.lockSuffix == ".lock")
        #expect(SoakPlan.fsckTarget == "data.img")
        #expect(SoakPlan.fsckFlag == "-n")
        #expect(SoakPlan.coreProcessName == "gmak8-core")
        #expect(SoakPlan.launchAgentLabel == "dev.gmak8.core")
        #expect(SoakPlan.helpersDirectory == "Contents/Helpers")
    }

    @Test func runnerLabelIsSelfHostedGmak8VM() {
        #expect(SoakPlan.runnerLabel == "gmak8-vm")
        #expect(SoakPlan.runnerLabels == ["self-hosted", "gmak8-vm"])
        #expect(SoakPlan.githubHostedMacImages.contains("macos-15"))
    }

    @Test func workflowIsManualSelfHostedAndNotGitHubMac() throws {
        let yaml = try String(contentsOf: soakWorkflowURL(), encoding: .utf8)
        #expect(yaml.contains("workflow_dispatch"))
        #expect(yaml.contains("gmak8-vm"))
        #expect(yaml.contains("self-hosted"))
        #expect(yaml.contains("scripts/soak.sh --live"))
        #expect(yaml.contains("scripts/soak.sh --plan"))
        #expect(!yaml.contains("macos-15"))
        #expect(!yaml.contains("macos-latest"))
        #expect(!yaml.contains("pull_request"))
        for image in SoakPlan.githubHostedMacImages {
            #expect(!yaml.contains(image))
        }
    }

    @Test func ciDoesNotInvokeLiveSoak() throws {
        let ci = try String(contentsOf: repoRoot().appending(path: "scripts/ci.sh"), encoding: .utf8)
        #expect(ci.contains("scripts/soak.sh --self-test"))
        #expect(!ci.contains("soak.sh --live"))
    }

    @Test func soakScriptPlanMatchesKit() throws {
        let plan09 = try runSoak(["--plan", "--gate", "0.9", "--cycles", "50"])
        #expect(plan09.status == 0)
        #expect(plan09.stdout.contains("GATE=0.9"))
        #expect(plan09.stdout.contains("RUNNER_LABEL=gmak8-vm"))
        #expect(plan09.stdout.contains("RUNS_ON=self-hosted,gmak8-vm"))
        #expect(plan09.stdout.contains("CYCLES=50"))
        #expect(plan09.stdout.contains("NODEPORT_HOST=127.0.0.1"))
        #expect(plan09.stdout.contains("STEPS=\(SoakPlan.joinedSteps(gate: SoakPlan.gate09))"))
        #expect(plan09.stdout.contains("VIRTCTL=0"))
        #expect(plan09.stdout.contains("VIRTCTL_LIVE=0"))
        #expect(plan09.stdout.contains("DOCKER_HUB=0"))
        #expect(plan09.stdout.contains("DISK_ATTACHMENT=nvme"))
        #expect(plan09.stdout.contains("DISK_CACHE=cached"))
        #expect(plan09.stdout.contains("DISK_SYNC=full"))
        #expect(plan09.stdout.contains("DISK_FORBIDDEN=virtio-blk"))
        #expect(plan09.stdout.contains("LOCK_UNLINK=0"))
        #expect(plan09.stdout.contains("GITHUB_HOSTED=0"))
        #expect(plan09.stdout.contains("WORKFLOW_DISPATCH=1"))
        #expect(!plan09.stdout.contains("virtctlPortForwardStdio"))

        let plan10 = try runSoak(["--plan", "--gate", "1.0"])
        #expect(plan10.status == 0)
        #expect(plan10.stdout.contains("GATE=1.0"))
        #expect(plan10.stdout.contains("virtctlPortForwardStdio"))
        #expect(plan10.stdout.contains("VIRTCTL=1"))
        #expect(plan10.stdout.contains("VIRTCTL_LIVE=0"))
        #expect(plan10.stdout.contains("u1NanoClusterInstancetype"))
    }

    @Test func soakSelfTestPassesWithoutBooting() throws {
        let result = try runSoak(["--self-test"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("soak self-test: ok"))
        #expect(!result.stdout.lowercased().contains("vzvirtualmachine"))
    }

    @Test func liveRefusesGitHubHostedMacOS() throws {
        let result = try runSoak(
            ["--live", "--cycles", "1"],
            environment: ["RUNNER_ENVIRONMENT": "github-hosted", "ImageOS": "macos15"]
        )
        #expect(result.status != 0)
        #expect(result.stderr.contains("GitHub-hosted"))
    }
}

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func soakWorkflowURL() -> URL {
    repoRoot().appending(path: SoakPlan.workflowFile)
}

private func soakScriptURL() -> URL {
    repoRoot().appending(path: SoakPlan.scriptFile)
}

private struct SoakProcessResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

private func runSoak(
    _ arguments: [String],
    environment: [String: String] = [:]
) throws -> SoakProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [soakScriptURL().path(percentEncoded: false)] + arguments
    process.currentDirectoryURL = repoRoot()
    if !environment.isEmpty {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
    }
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
    return SoakProcessResult(
        status: process.terminationStatus,
        stdout: String(data: outData, encoding: .utf8) ?? "",
        stderr: String(data: errData, encoding: .utf8) ?? ""
    )
}
