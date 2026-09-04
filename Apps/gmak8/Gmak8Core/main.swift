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
    let settingsForConfig = loadCoreSettings(from: paths)
    try writeClusterConfig(directory: paths.configDirectory, settings: settingsForConfig)

    let controller = LinuxEFIVirtualMachineRuntime(
        layout: layout,
        hardware: hardware,
        network: network,
        configShareDirectory: paths.configDirectory,
        hostShares: hostDirectoryShares(from: settingsForConfig)
    )
    let setCurrentContext = settingsForConfig.setCurrentContextOnStart
    let makeClient: @Sendable () async throws -> GuestAgentClient = {
        let device = try await controller.virtioSocketDevice()
        return VZGuestAgentConnector.makeClient(device: device, queue: VirtualMachineQueue.shared)
    }
    let kubevirtAirgap: (any AirgapProviding)? = {
        guard settingsForConfig.kubeVirtEnabled else {
            return nil
        }
        let pin = KubeVirtAirgapPin.bundled
        if pin.signed.hasStubDigest {
            return nil
        }
        return HostAirgapProvider(
            paths: paths,
            pin: AirgapPin(
                k3sVersion: pin.kubevirtVersion,
                fileName: pin.fileName,
                url: pin.url,
                sha256: pin.sha256,
                maxBytes: pin.maxBytes,
                guestImagesDirectory: AirgapPin.guestImagesDirectory
            ))
    }()
    let bringUp = KubernetesBringUp(
        makeClient: makeClient,
        kubeconfigStore: KubeconfigStore.current(),
        setCurrentContext: setCurrentContext,
        airgapProvider: HostAirgapProvider(paths: paths),
        kubevirtAirgapProvider: kubevirtAirgap,
        installKubeVirt: settingsForConfig.kubeVirtEnabled,
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
    let nestedVirt = NestedVirtualization.isSupported
    Gmak8Log.core.info("nested virt enabled=\(nestedVirt, privacy: .public)")
    let engine = ClusterEngine(
        scheduler: DispatchEngineScheduler(),
        nestedVirt: nestedVirt,
        runtime: CoreVirtualMachineRuntime(
            controller: controller,
            configDirectory: paths.configDirectory
        ),
        bringUp: bringUp,
        publisher: publisher,
        diskReset: HostClusterDiskReset(paths: paths),
        processExit: processExit,
        images: GuestNodeImageRuntime(makeClient: makeClient)
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
