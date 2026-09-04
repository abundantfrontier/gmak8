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
            let settings = loadCoreSettings(from: .current())
            try writeClusterConfig(directory: configDirectory, settings: settings)
            controller.hostShares = hostDirectoryShares(from: settings)
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

func loadCoreSettings(from paths: HostPaths) -> Settings {
    guard FileManager.default.fileExists(atPath: paths.settingsFile.path(percentEncoded: false)),
        let loaded = try? Settings.load(from: paths.settingsFile)
    else {
        return Settings(profile: .kubernetes, cpu: 4, memoryGiB: 6, dataDiskGiB: 60)
    }
    return loaded
}

func writeClusterConfig(directory: URL, settings: Settings) throws {
    try ClusterConfigFiles.write(
        directory: directory,
        settings: settings,
        proxy: SystemProxy.fromSystem()
    )
    if settings.profile == .eureka {
        let yamlURL = directory.appending(path: "k3s/config.yaml")
        let yaml = (try? String(contentsOf: yamlURL, encoding: .utf8)) ?? ""
        if !K3sConfig.hasDataDiskLocalPath(yaml) {
            throw ClusterBringUpError(
                message: "Eureka profile requires default-local-storage-path: /mnt/data/local-path")
        }
    }
}

func hostDirectoryShares(from settings: Settings) -> [HostDirectoryShare] {
    settings.hostMounts.map {
        HostDirectoryShare(
            tag: $0.tag,
            url: URL(fileURLWithPath: $0.path),
            readOnly: $0.readOnly
        )
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
