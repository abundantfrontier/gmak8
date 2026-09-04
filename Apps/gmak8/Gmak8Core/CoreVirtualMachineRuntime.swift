import Foundation
import Gmak8Kit
import Gmak8Virtualization
import Gmak8XPC

struct CoreVirtualMachineRuntime: VirtualMachineRuntime {
    let controller: LinuxEFIVirtualMachineRuntime
    let configDirectory: URL

    var stepName: String { "vm" }

    func preflight() -> VirtualMachinePreflightError? {
        do {
            try K3sConfig.writeHostFile(directory: configDirectory)
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

    func cancelInFlightStart() {
        controller.cancelInFlightStart()
    }

    func setDegradedHandler(_ handler: (@Sendable (String) -> Void)?) {
        controller.setDegradedHandler(handler)
    }
}

struct GVProxyHostPortExposer: HostPortExposer {
    var socketURL: URL

    func expose(hostPort: Int, guestPort: Int) throws {
        let request: GVProxyExposeRequest
        do {
            request = try GVProxyExposeRequest(hostPort: hostPort, guestPort: guestPort)
        } catch {
            if GuestNetwork.forbiddenHostPorts.contains(hostPort) {
                throw HostPortExposeError.forbidden(hostPort)
            }
            throw HostPortExposeError.failed(String(describing: error))
        }
        do {
            try UnixHTTPClient(socketURL: socketURL).expose(request)
        } catch let error as VirtualMachineError {
            if case .networkFailed(let reason) = error, reason.lowercased().contains("address already in use") {
                throw HostPortExposeError.addressInUse(hostPort)
            }
            throw HostPortExposeError.failed(error.recoveryMessage)
        }
    }

    func unexpose(hostPort: Int) throws {
        try UnixHTTPClient(socketURL: socketURL, timeout: 2).unexpose(hostPort: hostPort)
    }
}

private func engineErrorCode(for error: VirtualMachineError) -> EngineErrorCode {
    switch error {
    case .unsupported:
        return .virtualizationUnsupported
    case .diskImagesLocked:
        return .locked
    case .osImageMissing, .osImageEmpty, .posix, .configurationFailed, .startFailed, .stoppedDuringStart,
        .stopFailed, .socketPathTooLong, .gvproxyMissing, .networkFailed:
        return .invalidRequest
    }
}
