import Foundation
import Gmak8Virtualization
import Gmak8XPC

struct CoreVirtualMachineRuntime: VirtualMachineRuntime {
    let controller: LinuxEFIVirtualMachineRuntime

    var stepName: String { "vm" }

    func preflight() -> VirtualMachinePreflightError? {
        do {
            try controller.prepare()
            return nil
        } catch let error as VirtualMachineError {
            return VirtualMachinePreflightError(code: engineErrorCode(for: error), message: error.recoveryMessage)
        } catch {
            return VirtualMachinePreflightError(code: .invalidRequest, message: error.localizedDescription)
        }
    }

    func start(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        controller.start(completion: completion)
    }

    func stop(completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        controller.stop(completion: completion)
    }

    func setUnexpectedStopHandler(_ handler: (@Sendable (Error?) -> Void)?) {
        controller.setUnexpectedStopHandler(handler)
    }
}

private func engineErrorCode(for error: VirtualMachineError) -> EngineErrorCode {
    switch error {
    case .unsupported:
        return .virtualizationUnsupported
    case .diskImagesLocked:
        return .locked
    case .osImageMissing, .posix, .configurationFailed, .startFailed, .stoppedDuringStart, .stopFailed:
        return .invalidRequest
    }
}
