import Foundation
import Testing

@testable import Gmak8Virtualization

struct GVProxyLaunchTests {
    @Test func argumentsUseUnixgramAndLoopbackOnly() throws {
        let http = URL(fileURLWithPath: "/tmp/gmak8-g.sock")
        let vfkit = URL(fileURLWithPath: "/tmp/gmak8-n.sock")
        let args = try GVProxyLaunch.arguments(httpSocket: http, vfkitSocket: vfkit)
        #expect(
            args == [
                "--listen", "unix:///tmp/gmak8-g.sock",
                "--listen-vfkit", "unixgram:///tmp/gmak8-n.sock",
                "--mtu", "1500",
                "--ssh-port", "-1",
            ])
        #expect(args.contains(where: { $0.contains("unixgram://") }))
        #expect(!args.contains(where: { $0.contains("0.0.0.0") }))
        #expect(!args.joined(separator: " ").contains("0.0.0.0"))
    }

    @Test func argumentsFailWhenVfkitPathExceedsSunPath() {
        let tooLong = URL(fileURLWithPath: "/" + String(repeating: "x", count: 120) + "/n.sock")
        #expect(throws: VirtualMachineError.socketPathTooLong(tooLong)) {
            try GVProxyLaunch.arguments(
                httpSocket: URL(fileURLWithPath: "/tmp/g.sock"),
                vfkitSocket: tooLong
            )
        }
    }

    @Test func bundledHelperIsContentsHelpersNotMacOSHelpers() {
        let core = URL(fileURLWithPath: "/Applications/gmak8.app/Contents/MacOS/gmak8-core")
        #expect(
            GVProxyLaunch.bundledHelperURL(from: core).path(percentEncoded: false)
                == "/Applications/gmak8.app/Contents/Helpers/gvproxy"
        )
        let app = URL(fileURLWithPath: "/Applications/gmak8.app")
        #expect(
            GVProxyLaunch.bundledHelperURL(from: app).path(percentEncoded: false)
                == "/Applications/gmak8.app/Contents/Helpers/gvproxy"
        )
    }

    @Test func resolvePrefersOverrideThenHelpersThenBringUpNotPATH() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let decoyDir = root.appending(path: "path-decoy", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: true)
        let decoy = decoyDir.appending(path: "gvproxy")
        try "#!/bin/sh\n".write(to: decoy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: UnixgramPath.fileSystemPath(decoy)
        )

        let macos = root.appending(path: "gmak8.app/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let core = macos.appending(path: "gmak8-core")
        try Data().write(to: core)
        let helpers = root.appending(path: "gmak8.app/Contents/Helpers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let bundled = helpers.appending(path: "gvproxy")
        try "#!/bin/sh\n".write(to: bundled, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: UnixgramPath.fileSystemPath(bundled)
        )

        let env = ["PATH": UnixgramPath.fileSystemPath(decoyDir), "GMAK8_GVPROXY": ""]
        let found = GVProxyLaunch.resolveExecutable(
            environment: env,
            executableURL: core,
            currentDirectory: root
        )
        #expect(found?.standardizedFileURL == bundled.standardizedFileURL)

        let override = root.appending(path: "custom-gvproxy")
        try "#!/bin/sh\n".write(to: override, atomically: true, encoding: .utf8)
        let overridden = GVProxyLaunch.resolveExecutable(
            environment: [GVProxyLaunch.environmentOverrideKey: UnixgramPath.fileSystemPath(override)],
            executableURL: core,
            currentDirectory: root
        )
        #expect(overridden?.standardizedFileURL == override.standardizedFileURL)

        let empty = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: empty) }
        let ignoredPATH = GVProxyLaunch.resolveExecutable(
            environment: ["PATH": UnixgramPath.fileSystemPath(decoyDir)],
            executableURL: empty.appending(path: "no-such-core"),
            currentDirectory: empty
        )
        #expect(ignoredPATH == nil)
    }

    @Test func resolveFindsThirdPartyBringUpBinary() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "ThirdParty/gvproxy/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let helper = bin.appending(path: "gvproxy")
        try "#!/bin/sh\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: UnixgramPath.fileSystemPath(helper)
        )
        let nested = root.appending(path: "Apps/gmak8", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let found = GVProxyLaunch.resolveExecutable(
            environment: [:],
            executableURL: nested.appending(path: "gmak8-core"),
            currentDirectory: nested
        )
        #expect(found?.standardizedFileURL == helper.standardizedFileURL)
    }
}
