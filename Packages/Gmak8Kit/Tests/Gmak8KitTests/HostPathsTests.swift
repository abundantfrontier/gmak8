import Darwin
import Foundation
import Testing

@testable import Gmak8Kit

struct HostPathsTests {
    @Test func applicationSupportHoldsSettingsEngineKubeconfigAndVM() {
        let paths = HostPaths.current()
        #expect(paths.applicationSupport.lastPathComponent == "dev.gmak8.app")
        #expect(paths.applicationSupport.deletingLastPathComponent().lastPathComponent == "Application Support")
        #expect(paths.settingsFile.lastPathComponent == "settings.json")
        #expect(paths.engineSocket.lastPathComponent == "engine.sock")
        #expect(paths.kubeconfigFile.lastPathComponent == "kubeconfig")
        #expect(paths.configDirectory.lastPathComponent == "config")
        #expect(paths.configDirectory.deletingLastPathComponent() == paths.applicationSupport)
        #expect(paths.vmDirectory.lastPathComponent == "vm")
        #expect(paths.osImage.lastPathComponent == "os.img")
        #expect(paths.dataImage.lastPathComponent == "data.img")
        #expect(paths.efiNVRAM.lastPathComponent == "efi-nvram.bin")
        #expect(paths.serialLog.lastPathComponent == "serial.log")
        #expect(paths.osImage.deletingLastPathComponent() == paths.vmDirectory)
        #expect(paths.dataImage.deletingLastPathComponent() == paths.vmDirectory)
        #expect(paths.efiNVRAM.deletingLastPathComponent() == paths.vmDirectory)
        #expect(paths.serialLog.deletingLastPathComponent() == paths.vmDirectory)
        #expect(paths.settingsFile.deletingLastPathComponent() == paths.applicationSupport)
        #expect(paths.engineSocket.deletingLastPathComponent() == paths.applicationSupport)
        #expect(paths.kubeconfigFile.deletingLastPathComponent() == paths.applicationSupport)
        #expect(paths.vmDirectory.deletingLastPathComponent() == paths.applicationSupport)
    }

    @Test func cachesHoldsShortUnixgramSockets() {
        let paths = HostPaths.current()
        #expect(paths.caches.lastPathComponent == "dev.gmak8.app")
        #expect(paths.caches.deletingLastPathComponent().lastPathComponent == "Caches")
        #expect(paths.vfkitSocket.lastPathComponent == "n.sock")
        #expect(paths.gvproxySocket.lastPathComponent == "g.sock")
        #expect(paths.buildkitSocket.lastPathComponent == "buildkit.sock")
        #expect(paths.vfkitSocket.deletingLastPathComponent() == paths.caches)
        #expect(paths.gvproxySocket.deletingLastPathComponent() == paths.caches)
        #expect(paths.buildkitSocket.deletingLastPathComponent() == paths.caches)
    }

    @Test func logsDirectoryIsLibraryLogsGmak8() {
        let paths = HostPaths.current()
        #expect(paths.logs.lastPathComponent == "gmak8")
        #expect(paths.logs.deletingLastPathComponent().lastPathComponent == "Logs")
        #expect(paths.gvproxyLog.lastPathComponent == "gvproxy.log")
        #expect(paths.gvproxyLog.deletingLastPathComponent() == paths.logs)
    }

    @Test func unixgramSocketsFitDarwinSunPath() {
        #expect(MemoryLayout.size(ofValue: sockaddr_un().sun_path) == 104)
        #expect(HostPaths.unixgramSunPathByteCount == 104)
        let paths = HostPaths.current()
        #expect(HostPaths.unixgramPathFits(paths.vfkitSocket))
        #expect(HostPaths.unixgramPathFits(paths.gvproxySocket))
        #expect(HostPaths.unixgramPathFits(paths.buildkitSocket))
        let applicationSupportVfkit = paths.applicationSupport.appending(path: "n.sock")
        #expect(
            paths.vfkitSocket.path(percentEncoded: false).utf8.count
                < applicationSupportVfkit.path(percentEncoded: false).utf8.count
        )
    }

    @Test func unixgramPathFitsSunPathBoundary() {
        let fits = URL(fileURLWithPath: "/" + String(repeating: "x", count: 102))
        let tooLong = URL(fileURLWithPath: "/" + String(repeating: "x", count: 103))
        #expect(fits.withUnsafeFileSystemRepresentation { $0.map(strlen) } == 103)
        #expect(tooLong.withUnsafeFileSystemRepresentation { $0.map(strlen) } == 104)
        #expect(HostPaths.unixgramPathFits(fits))
        #expect(!HostPaths.unixgramPathFits(tooLong))

        let overLong = URL(
            fileURLWithPath:
                "/Users/\(String(repeating: "u", count: 80))/Library/Application Support/dev.gmak8.app/n.sock"
        )
        #expect(!HostPaths.unixgramPathFits(overLong))
    }

    @Test func layoutUnderExplicitHome() {
        let paths = HostPaths(
            applicationSupport: URL(fileURLWithPath: "/Users/tester/Library/Application Support/dev.gmak8.app"),
            caches: URL(fileURLWithPath: "/Users/tester/Library/Caches/dev.gmak8.app"),
            logs: URL(fileURLWithPath: "/Users/tester/Library/Logs/gmak8")
        )
        #expect(
            paths.settingsFile.path(percentEncoded: false)
                == "/Users/tester/Library/Application Support/dev.gmak8.app/settings.json"
        )
        #expect(
            paths.vfkitSocket.path(percentEncoded: false)
                == "/Users/tester/Library/Caches/dev.gmak8.app/n.sock"
        )
        #expect(paths.logs.path(percentEncoded: false) == "/Users/tester/Library/Logs/gmak8")
    }
}
