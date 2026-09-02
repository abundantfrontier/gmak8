import Foundation

public struct CLIBinaryCopy: Equatable, Sendable {
    public var name: String
    public var source: URL
    public var destination: URL

    public init(name: String, source: URL, destination: URL) {
        self.name = name
        self.source = source
        self.destination = destination
    }
}

public struct CLIInstallPlan: Equatable, Sendable {
    public var destinationDirectory: URL
    public var binaries: [CLIBinaryCopy]
    public var skippedVirtctl: Bool
    public var missingGmak8Helper: Bool
    public var pathExportNeeded: Bool
    public var homebrewBinDetected: Bool

    public init(
        destinationDirectory: URL,
        binaries: [CLIBinaryCopy],
        skippedVirtctl: Bool,
        missingGmak8Helper: Bool,
        pathExportNeeded: Bool,
        homebrewBinDetected: Bool
    ) {
        self.destinationDirectory = destinationDirectory
        self.binaries = binaries
        self.skippedVirtctl = skippedVirtctl
        self.missingGmak8Helper = missingGmak8Helper
        self.pathExportNeeded = pathExportNeeded
        self.homebrewBinDetected = homebrewBinDetected
    }
}

public enum CLIInstallError: Error, Equatable, LocalizedError, Sendable {
    case notWritable(URL)

    public var errorDescription: String? {
        switch self {
        case .notWritable(let url):
            return
                "Could not write \(url.path(percentEncoded: false)) without admin. gmak8 never requires an administrator password."
        }
    }
}

public enum CLIPathInstaller {
    public static let relativeBinPath = ".local/bin"
    public static let homebrewBinPath = "/opt/homebrew/bin"
    public static let pathExportSnippet = #"export PATH="$HOME/.local/bin:$PATH""#
    public static let gmak8HelperName = "gmak8"
    public static let virtctlHelperName = "virtctl"
    public static let executablePermissions = 0o755

    public static func defaultDestination(home: URL) -> URL {
        home.appending(path: relativeBinPath, directoryHint: .isDirectory)
    }

    public static func helpersDirectory(bundleURL: URL) -> URL {
        if bundleURL.pathExtension == "app" {
            return
                bundleURL
                .appending(path: "Contents", directoryHint: .isDirectory)
                .appending(path: "Helpers", directoryHint: .isDirectory)
        }
        let parent = bundleURL.deletingLastPathComponent()
        if parent.lastPathComponent == "MacOS" {
            return
                parent
                .deletingLastPathComponent()
                .appending(path: "Helpers", directoryHint: .isDirectory)
        }
        return parent.appending(path: "Helpers", directoryHint: .isDirectory)
    }

    public static func helperURL(name: String, bundleURL: URL, fileManager: FileManager) -> URL? {
        let url = helpersDirectory(bundleURL: bundleURL).appending(path: name)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            return url
        }
        return nil
    }

    public static func isOnPATH(_ directory: URL, pathEnvironment: String) -> Bool {
        let want = normalizedPath(directory)
        for entry in pathEnvironment.split(separator: ":") {
            if normalizedPath(URL(fileURLWithPath: String(entry))) == want {
                return true
            }
        }
        return false
    }

    public static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    public static func homebrewBin(fileManager: FileManager, path: String = homebrewBinPath) -> URL? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return url
        }
        return nil
    }

    public static func plan(
        home: URL,
        pathEnvironment: String,
        bundleURL: URL,
        fileManager: FileManager = .default,
        homebrewBinPath: String = homebrewBinPath
    ) -> CLIInstallPlan {
        let dest = defaultDestination(home: home)
        var binaries: [CLIBinaryCopy] = []
        let gmak8 = helperURL(name: gmak8HelperName, bundleURL: bundleURL, fileManager: fileManager)
        if let gmak8 {
            binaries.append(
                CLIBinaryCopy(
                    name: gmak8HelperName,
                    source: gmak8,
                    destination: dest.appending(path: gmak8HelperName)
                )
            )
        }
        let virtctl = helperURL(name: virtctlHelperName, bundleURL: bundleURL, fileManager: fileManager)
        if let virtctl {
            binaries.append(
                CLIBinaryCopy(
                    name: virtctlHelperName,
                    source: virtctl,
                    destination: dest.appending(path: virtctlHelperName)
                )
            )
        }
        return CLIInstallPlan(
            destinationDirectory: dest,
            binaries: binaries,
            skippedVirtctl: virtctl == nil,
            missingGmak8Helper: gmak8 == nil,
            pathExportNeeded: !isOnPATH(dest, pathEnvironment: pathEnvironment),
            homebrewBinDetected: homebrewBin(fileManager: fileManager, path: homebrewBinPath) != nil
        )
    }

    public static func install(_ plan: CLIInstallPlan, fileManager: FileManager = .default) throws {
        if plan.binaries.isEmpty {
            return
        }
        try fileManager.createDirectory(at: plan.destinationDirectory, withIntermediateDirectories: true)
        if !fileManager.isWritableFile(atPath: plan.destinationDirectory.path(percentEncoded: false)) {
            throw CLIInstallError.notWritable(plan.destinationDirectory)
        }
        for binary in plan.binaries {
            try AtomicFileReplace.copy(
                from: binary.source,
                to: binary.destination,
                posixPermissions: executablePermissions,
                fileManager: fileManager
            )
        }
    }
}
