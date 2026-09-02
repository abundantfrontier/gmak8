import Darwin
import Foundation
import Gmak8Kit
import Gmak8XPC

signal(SIGPIPE, SIG_IGN)

let paths = HostPaths.current()
do {
    try FileManager.default.createDirectory(
        at: paths.applicationSupport,
        withIntermediateDirectories: true
    )
    let engine = ClusterEngine(scheduler: DispatchEngineScheduler())
    let server = try EngineSocketServer(socketURL: paths.engineSocket, engine: engine)
    Gmak8Log.core.info("gmak8-core listening on engine.sock")
    try server.run()
} catch {
    Gmak8Log.core.error(
        "gmak8-core failed: \(error.localizedDescription, privacy: .public)"
    )
    exit(1)
}
