import Darwin
import Foundation
import Gmak8GuestClient
import Gmak8Kit
import Gmak8Virtualization
import Gmak8XPC

signal(SIGPIPE, SIG_IGN)

let paths = HostPaths.current()
do {
    try FileManager.default.createDirectory(
        at: paths.applicationSupport,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: paths.caches,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: paths.logs,
        withIntermediateDirectories: true
    )
    try TimeMachineExclusion.excludeVMDirectory(at: paths.vmDirectory)

    var layout = VMDiskLayout.under(vmDirectory: paths.vmDirectory)
    layout.createOSImageIfMissing = false
    if let osImage = VMDefaults.osImageURL() {
        layout.osImage = osImage
    }

    let hardware = loadHardware(paths: paths)
    let network = GVProxyNetworkStack(
        executable: GVProxyLaunch.resolveExecutable(),
        httpSocket: paths.gvproxySocket,
        vfkitSocket: paths.vfkitSocket,
        logFile: paths.gvproxyLog
    )
    try FileManager.default.createDirectory(
        at: paths.configDirectory,
        withIntermediateDirectories: true
    )
    try K3sConfig.writeHostFile(directory: paths.configDirectory)

    let controller = LinuxEFIVirtualMachineRuntime(
        layout: layout,
        hardware: hardware,
        network: network,
        configShareDirectory: paths.configDirectory
    )
    let setCurrentContext: Bool = {
        guard FileManager.default.fileExists(atPath: paths.settingsFile.path(percentEncoded: false)) else {
            return false
        }
        return (try? Settings.load(from: paths.settingsFile))?.setCurrentContextOnStart ?? false
    }()
    let makeClient: @Sendable () async throws -> GuestAgentClient = {
        let device = try await controller.virtioSocketDevice()
        return VZGuestAgentConnector.makeClient(device: device, queue: VirtualMachineQueue.shared)
    }
    let bringUp = KubernetesBringUp(
        makeClient: makeClient,
        kubeconfigStore: KubeconfigStore.current(),
        setCurrentContext: setCurrentContext,
        airgapProvider: HostAirgapProvider(paths: paths),
        apiPort: { controller.apiHostPort }
    )
    let settingsURL = paths.settingsFile
    let publisher = NodePortPublisher(
        source: AgentServiceSource(makeClient: makeClient),
        exposer: GVProxyHostPortExposer(socketURL: paths.gvproxySocket),
        isEnabled: {
            guard FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)) else {
                return true
            }
            return (try? Settings.load(from: settingsURL))?.publishNodePorts ?? true
        },
        baseline: {
            [
                PublishedPort.loopback(
                    service: "kubernetes",
                    namespace: "default",
                    port: GuestNetwork.apiGuestPort,
                    nodePort: GuestNetwork.apiGuestPort,
                    hostPort: controller.apiHostPort,
                    guestPort: GuestNetwork.apiGuestPort,
                    scheme: "https",
                    preferredHostPort: GuestNetwork.apiHostPort
                ),
                PublishedPort.loopback(
                    service: "http",
                    port: GuestNetwork.httpGuestPort,
                    nodePort: GuestNetwork.httpGuestPort,
                    hostPort: controller.httpHostPort,
                    guestPort: GuestNetwork.httpGuestPort,
                    scheme: "http",
                    preferredHostPort: GuestNetwork.httpHostPort
                ),
                PublishedPort.loopback(
                    service: "https",
                    port: GuestNetwork.httpsGuestPort,
                    nodePort: GuestNetwork.httpsGuestPort,
                    hostPort: controller.httpsHostPort,
                    guestPort: GuestNetwork.httpsGuestPort,
                    scheme: "https",
                    preferredHostPort: GuestNetwork.httpsHostPort
                ),
            ]
        }
    )
    let processExit = CoreProcessExit()
    let engine = ClusterEngine(
        scheduler: DispatchEngineScheduler(),
        runtime: CoreVirtualMachineRuntime(
            controller: controller,
            configDirectory: paths.configDirectory
        ),
        bringUp: bringUp,
        publisher: publisher,
        diskReset: HostClusterDiskReset(paths: paths),
        processExit: processExit
    )
    let server = try EngineSocketServer(socketURL: paths.engineSocket, engine: engine)
    processExit.setHandler { code in
        server.stop()
        Foundation.exit(code)
    }
    Gmak8Log.core.info("gmak8-core listening on engine.sock")
    try server.run()
} catch let code as EngineErrorCode where code == .locked {
    Gmak8Log.core.info("gmak8-core already running")
    exit(0)
} catch {
    Gmak8Log.core.error(
        "gmak8-core failed: \(error.localizedDescription, privacy: .public)"
    )
    exit(1)
}

private func loadHardware(paths: HostPaths) -> VMHardware {
    let settingsPath = paths.settingsFile.path(percentEncoded: false)
    if FileManager.default.fileExists(atPath: settingsPath) {
        do {
            let settings = try Settings.load(from: paths.settingsFile)
            return VMHardware(
                cpuCount: settings.cpu,
                memoryBytes: UInt64(settings.memoryGiB) * VMHardware.gibibyte,
                osDiskBytes: VMHardware.defaultOSDiskBytes,
                dataDiskBytes: UInt64(settings.dataDiskGiB) * VMHardware.gibibyte
            )
        } catch {
            Gmak8Log.core.error(
                "settings.json unreadable: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    return VMHardware.kubernetesDefaults(
        processorCount: ProcessInfo.processInfo.processorCount,
        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
    )
}
