import Foundation
import Testing

@testable import Gmak8XPC

struct RecoveryKindTests {
    @Test func fakeEngineClassifiesLastErrorKinds() {
        let cases: [(String, RecoveryKind)] = [
            (RecoveryCopy.diskImagesLocked, .diskImagesLocked),
            (RecoveryCopy.translocated, .translocatedApp),
            ("SQLite database is corrupt (database disk image is malformed)", .sqliteCorrupt),
            (RecoveryCopy.loginItemDenied, .loginItemDenied),
            (RecoveryCopy.nestedVirtUnavailable, .nestedVirtUnavailable),
            (RecoveryCopy.hypervisorPressure, .hypervisorPressure),
            (RecoveryCopy.unsupportedHardware, .vmPanic),
            ("Virtual machine failed to start: VZError panic", .vmPanic),
            ("data disk has 1 bytes free; airgap import needs 120 (archive + 20%)", .diskFull),
            ("Network stack failed: listen tcp 127.0.0.1:6443: bind: address already in use", .apiPortConflict),
            ("listen tcp 127.0.0.1:16443: bind: address already in use", .apiPortConflict),
            ("listen tcp 127.0.0.1:8080: bind: address already in use", .ingressPortConflict),
            ("listen tcp 127.0.0.1:8443: bind: address already in use", .ingressPortConflict),
            ("30663 in use by pid 221 (nginx)", .nodePortCollision),
            ("Timed out waiting for kubernetes", .kubernetesNotReady),
            (
                "On-disk k3s data is Kubernetes 1.32, but this gmak8 ships v1.33.3+k3s1. Reset the cluster.",
                .kubernetesNotReady
            ),
            ("k3s airgap Cosign signature verify failed", .guestAirgapVerifyFailed),
            (
                "k3s airgap archive missing at /tmp/x; first boot will not pull docker.io/rancher.",
                .guestAirgapVerifyFailed
            ),
            ("Timed out waiting for guestAgent", .agentTimeout),
        ]
        for item in cases {
            let kind = RecoveryKind.classify(lastError: item.0)
            #expect(kind == item.1, "\(item.0) -> \(kind) want \(item.1)")
        }
    }

    @Test func fakeEngineLockedDiskClassifiesFromLastError() {
        let runtime = RecoveryStubRuntime(
            preflightError: VirtualMachinePreflightError(
                code: .locked,
                message: RecoveryCopy.diskImagesLocked
            )
        )
        let engine = ClusterEngine(scheduler: ManualEngineScheduler(), runtime: runtime)
        #expect(engine.submit(.start) == .error(.locked))
        let status = engine.currentStatus()
        let plan = RecoveryPlan.make(status: status)
        #expect(plan.kind == .diskImagesLocked)
        #expect(plan.message == RecoveryCopy.diskImagesLocked)
        #expect(plan.message.contains("data.img"))
        #expect(plan.message.contains("engine.sock"))
        #expect(status.lastError == RecoveryCopy.diskImagesLocked)
    }

    @Test func fakeEngineSQLiteCorruptIsResetOnly() {
        let scheduler = ManualEngineScheduler()
        let runtime = RecoveryStubRuntime(
            startError: ClusterBringUpError(
                message: "SQLite database is corrupt (database disk image is malformed)"
            )
        )
        let engine = ClusterEngine(scheduler: scheduler, runtime: runtime)
        #expect(engine.submit(.start) == .ok)
        scheduler.runNext()
        let plan = RecoveryPlan.make(status: engine.currentStatus())
        #expect(plan.kind == .sqliteCorrupt)
        #expect(plan.actions == [.reset])
        #expect(!plan.actions.contains(.diagnosticsZip))
        #expect(plan.message.contains("Time Machine excludes vm/"))
        #expect(plan.message.contains("no snapshot"))
        #expect(!RecoveryAction.allCases.map(\.rawValue).contains { $0.lowercased().contains("snapshot") })
        #expect(!plan.actions.map(\.title).joined().lowercased().contains("snapshot"))
        #expect(engine.submit(.reset(force: false)) == .error(.confirmationRequired))
        #expect(ResetConfirmation.engineRequest == .reset(force: true))
        #expect(engine.submit(.reset(force: true)) == .ok)
    }

    @Test func translocationCopyIsExact() {
        #expect(RecoveryCopy.translocated == "Move gmak8 to /Applications and re-open.")
        let plan = RecoveryPlan.make(
            status: EngineStatus(state: .stopped, lastError: RecoveryCopy.translocated)
        )
        #expect(plan.kind == .translocatedApp)
        #expect(plan.message == RecoveryCopy.translocated)
        #expect(plan.actions == [.moveToApplications])
    }

    @Test func unsupportedHardwareIsNotLockOrHypervisorPressure() {
        let plan = RecoveryPlan.make(
            status: EngineStatus(state: .stopped, lastError: RecoveryCopy.unsupportedHardware)
        )
        #expect(plan.kind == .vmPanic)
        #expect(plan.kind != .hypervisorPressure)
        #expect(plan.kind != .diskImagesLocked)
        #expect(!plan.message.lowercased().contains("lock"))
        #expect(!plan.message.lowercased().contains("hypervisor"))
        #expect(plan.actions == [.diagnosticsZip, .restartVM, .reset])
    }

    @Test func publishedPortCollisionClassifiesWithoutLastError() {
        let port = PublishedPort(
            service: "web",
            hostPort: 30_663,
            guestPort: 30_663,
            collision: .collision
        )
        let plan = RecoveryPlan.make(
            status: EngineStatus(state: .running, lastError: nil, publishedPorts: [port])
        )
        #expect(plan.kind == .nodePortCollision)
        #expect(plan.message.contains("30663"))
        #expect(plan.actions.contains(.remapNodePort))
        #expect(plan.actions.contains(.skipNodePort))
    }

    @Test func extraErrorClassifiesTranslocationWhenStatusIsClean() {
        let plan = RecoveryPlan.make(
            status: EngineStatus(state: .stopped),
            extraError: RecoveryCopy.translocated
        )
        #expect(plan.kind == .translocatedApp)
    }

    @Test func resetConfirmationRequiresForce() {
        #expect(ResetConfirmation.confirmed(true))
        #expect(!ResetConfirmation.confirmed(false))
        #expect(ResetConfirmation.engineRequest == .reset(force: true))
        #expect(ResetConfirmation.informativeText.contains("Time Machine excludes vm/"))
        #expect(ResetConfirmation.informativeText.contains("no snapshot"))
    }

    @Test func diskFullDoesNotOfferResizeOrSnapshot() {
        let plan = RecoveryPlan.make(
            status: EngineStatus(state: .failed, lastError: "No space left on device")
        )
        #expect(plan.kind == .diskFull)
        #expect(plan.actions == [.revealImages, .pruneImages])
        let titles = plan.actions.map(\.title).joined(separator: " ").lowercased()
        #expect(!titles.contains("resize"))
        #expect(!titles.contains("snapshot"))
    }
}

private struct RecoveryStubRuntime: VirtualMachineRuntime {
    var stepName: String { "vm" }
    var preflightError: VirtualMachinePreflightError?
    var startError: ClusterBringUpError?

    init(preflightError: VirtualMachinePreflightError? = nil, startError: ClusterBringUpError? = nil) {
        self.preflightError = preflightError
        self.startError = startError
    }

    func preflight() -> VirtualMachinePreflightError? {
        preflightError
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        if let startError {
            completion(.failure(startError))
            return
        }
        completion(.success(()))
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        completion(.success(()))
    }
}
