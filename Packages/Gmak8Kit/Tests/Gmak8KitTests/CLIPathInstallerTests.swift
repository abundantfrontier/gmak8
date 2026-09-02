import Foundation
import Testing

@testable import Gmak8Kit

struct CLIPathInstallerTests {
    @Test func pathSnippetIsHomeLocalBinAndDoesNotUseZsh() {
        #expect(CLIPathInstaller.pathExportSnippet == #"export PATH="$HOME/.local/bin:$PATH""#)
        #expect(!CLIPathInstaller.pathExportSnippet.contains("zsh"))
        #expect(!CLIPathInstaller.pathExportSnippet.contains("-ilc"))
        let home = URL(fileURLWithPath: "/Users/tester")
        let dest = CLIPathInstaller.defaultDestination(home: home)
        #expect(CLIPathInstaller.normalizedPath(dest) == "/Users/tester/.local/bin")
        #expect(CLIPathInstaller.isOnPATH(dest, pathEnvironment: "/usr/bin:/bin") == false)
        #expect(CLIPathInstaller.isOnPATH(dest, pathEnvironment: "/Users/tester/.local/bin:/usr/bin"))
        #expect(CLIPathInstaller.homebrewBinPath == "/opt/homebrew/bin")
    }

    @Test func helpersComeFromAppBundleNotPATH() throws {
        let env = try CLIHarness()
        defer { env.tearDown() }

        try env.writeHelper("gmak8", contents: "gmak8-helper\n")
        try "path-gmak8\n".write(to: env.pathDir.appending(path: "gmak8"), atomically: true, encoding: .utf8)
        try "path-virtctl\n".write(to: env.pathDir.appending(path: "virtctl"), atomically: true, encoding: .utf8)

        let gmak8 = CLIPathInstaller.helperURL(
            name: CLIPathInstaller.gmak8HelperName,
            bundleURL: env.bundle,
            fileManager: .default
        )
        let virtctl = CLIPathInstaller.helperURL(
            name: CLIPathInstaller.virtctlHelperName,
            bundleURL: env.bundle,
            fileManager: .default
        )
        #expect(gmak8 == env.helpers.appending(path: "gmak8"))
        #expect(virtctl == nil)
        #expect(
            CLIPathInstaller.normalizedPath(CLIPathInstaller.helpersDirectory(bundleURL: env.bundle))
                .hasSuffix("Contents/Helpers")
        )

        let plan = CLIPathInstaller.plan(
            home: env.home,
            pathEnvironment: "\(env.pathDir.path(percentEncoded: false)):/usr/bin",
            bundleURL: env.bundle,
            homebrewBinPath: env.missingHomebrew.path(percentEncoded: false)
        )
        #expect(plan.binaries.map(\.name) == ["gmak8"])
        #expect(plan.skippedVirtctl)
        #expect(!plan.missingGmak8Helper)
        #expect(plan.pathExportNeeded)
        #expect(!plan.homebrewBinDetected)
        #expect(plan.destinationDirectory == CLIPathInstaller.defaultDestination(home: env.home))
    }

    @Test func virtctlIsCopiedWhenBundledAndSkippedWhenAbsent() throws {
        let env = try CLIHarness()
        defer { env.tearDown() }
        try env.writeHelper("gmak8", contents: "gmak8-helper\n")
        try env.writeHelper("virtctl", contents: "virtctl-helper\n")

        let localBin = CLIPathInstaller.defaultDestination(home: env.home).path(percentEncoded: false)
        let withVirtctl = CLIPathInstaller.plan(
            home: env.home,
            pathEnvironment: "\(localBin):/usr/bin",
            bundleURL: env.bundle,
            homebrewBinPath: env.homebrew.path(percentEncoded: false)
        )
        #expect(withVirtctl.binaries.map(\.name) == ["gmak8", "virtctl"])
        #expect(!withVirtctl.skippedVirtctl)
        #expect(!withVirtctl.pathExportNeeded)
        #expect(withVirtctl.homebrewBinDetected)

        try FileManager.default.removeItem(at: env.helpers.appending(path: "virtctl"))
        let skipped = CLIPathInstaller.plan(
            home: env.home,
            pathEnvironment: "/usr/bin",
            bundleURL: env.bundle,
            homebrewBinPath: env.missingHomebrew.path(percentEncoded: false)
        )
        #expect(skipped.skippedVirtctl)
        #expect(skipped.binaries.map(\.name) == ["gmak8"])
    }

    @Test func installWrites0755BinariesIntoHomeLocalBin() throws {
        let env = try CLIHarness()
        defer { env.tearDown() }
        try env.writeHelper("gmak8", contents: "gmak8-helper\n")

        let plan = CLIPathInstaller.plan(
            home: env.home,
            pathEnvironment: "/usr/bin",
            bundleURL: env.bundle,
            homebrewBinPath: env.missingHomebrew.path(percentEncoded: false)
        )
        try CLIPathInstaller.install(plan)
        let dest = plan.destinationDirectory.appending(path: "gmak8")
        let body = try String(contentsOf: dest, encoding: .utf8)
        #expect(body == "gmak8-helper\n")
        let mode =
            try FileManager.default.attributesOfItem(atPath: dest.path(percentEncoded: false))[.posixPermissions]
            as? NSNumber
        #expect(mode?.intValue == 0o755)
        #expect(
            !FileManager.default.fileExists(
                atPath: env.home.appending(path: "opt/homebrew/bin/gmak8").path(percentEncoded: false)
            )
        )
    }

    @Test func macosHelperPathResolvesContentsHelpers() {
        let executable = URL(fileURLWithPath: "/Applications/gmak8.app/Contents/MacOS/gmak8")
        #expect(
            CLIPathInstaller.normalizedPath(CLIPathInstaller.helpersDirectory(bundleURL: executable))
                == "/Applications/gmak8.app/Contents/Helpers"
        )
    }
}

private struct CLIHarness {
    var root: URL
    var home: URL
    var bundle: URL
    var helpers: URL
    var pathDir: URL
    var homebrew: URL
    var missingHomebrew: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-cli-path-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        home = root.appending(path: "home", directoryHint: .isDirectory)
        bundle = root.appending(path: "gmak8.app", directoryHint: .isDirectory)
        helpers =
            bundle
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Helpers", directoryHint: .isDirectory)
        pathDir = root.appending(path: "on-path", directoryHint: .isDirectory)
        homebrew = root.appending(path: "opt/homebrew/bin", directoryHint: .isDirectory)
        missingHomebrew = root.appending(path: "missing-homebrew", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homebrew, withIntermediateDirectories: true)
    }

    func writeHelper(_ name: String, contents: String) throws {
        try contents.write(to: helpers.appending(path: name), atomically: true, encoding: .utf8)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
