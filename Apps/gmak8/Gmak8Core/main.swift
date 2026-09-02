import Darwin
import Foundation
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
    try TimeMachineExclusion.excludeVMDirectory(at: paths.vmDirectory)

    var layout = VMDiskLayout.under(vmDirectory: paths.vmDirectory)
    if let osImage = VMDefaults.osImageURL() {
        layout.osImage = osImage
        layout.createOSImageIfMissing = false
    }

    let hardware: VMHardware
    if let settings = try? Settings.load(from: paths.settingsFile) {
        hardware = VMHardware(
            cpuCount: settings.cpu,
            memoryBytes: UInt64(settings.memoryGiB) * VMHardware.gibibyte,
            osDiskBytes: VMHardware.defaultOSDiskBytes,
            dataDiskBytes: UInt64(settings.dataDiskGiB) * VMHardware.gibibyte
        )
    } else {
        hardware = .bringUp
    }

    let controller = LinuxEFIVirtualMachineRuntime(layout: layout, hardware: hardware)
    let engine = ClusterEngine(
        scheduler: DispatchEngineScheduler(),
        runtime: CoreVirtualMachineRuntime(controller: controller)
    )
    let server = try EngineSocketServer(socketURL: paths.engineSocket, engine: engine)
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
