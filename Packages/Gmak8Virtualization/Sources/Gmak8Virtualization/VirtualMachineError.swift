import Foundation

public enum VirtualMachineError: Error, Equatable, Sendable {
    case unsupported
    case diskImagesLocked
    case osImageMissing(URL)
    case posix(errno: Int32, path: String)
    case configurationFailed(String)
    case startFailed(String)
    case stoppedDuringStart
    case stopFailed(String)

    /// Recovery copy. `unsupported` must not be described as a disk or hypervisor lock.
    public var recoveryMessage: String {
        switch self {
        case .unsupported:
            return
                "This Mac cannot run a virtual machine (unsupported CPU, OS, or missing virtualization entitlement)."
        case .diskImagesLocked:
            return "Another gmak8 (engine.sock live) holds data.img. Quit that instance."
        case .osImageMissing(let url):
            return "OS disk image is missing: \(url.path(percentEncoded: false))"
        case .posix(let errno, let path):
            return "Disk operation failed at \(path) (errno \(errno))."
        case .configurationFailed(let reason):
            return "Virtual machine configuration failed: \(reason)"
        case .startFailed(let reason):
            return "Virtual machine failed to start: \(reason)"
        case .stoppedDuringStart:
            return "Virtual machine start was cancelled."
        case .stopFailed(let reason):
            return "Virtual machine failed to stop: \(reason)"
        }
    }
}

extension VirtualMachineError: LocalizedError {
    public var errorDescription: String? {
        recoveryMessage
    }
}
