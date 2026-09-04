import AppKit
import Foundation
import Gmak8Kit

enum TerminalLauncher {
    static let terminalBundleIdentifier = "com.apple.Terminal"

    static func appleScriptSource(kubeconfigPath: String) -> String {
        let quoted = shellQuoted(kubeconfigPath)
        return """
            tell application "Terminal"
                activate
                do script "export KUBECONFIG=\(quoted)"
            end tell
            """
    }

    static func appleScriptSource(workingDirectory: String) -> String {
        let quoted = shellQuoted(workingDirectory)
        return """
            tell application "Terminal"
                activate
                do script "cd \(quoted) && echo 'Run: mkosi'"
            end tell
            """
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    @MainActor
    static func open(kubeconfig: URL = HostPaths.current().kubeconfigFile) {
        runAppleScript(appleScriptSource(kubeconfigPath: kubeconfig.path(percentEncoded: false)))
    }

    @MainActor
    static func open(workingDirectory: URL) {
        runAppleScript(appleScriptSource(workingDirectory: workingDirectory.path(percentEncoded: false)))
    }

    @MainActor
    private static func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if error == nil {
                return
            }
        }
        fallbackOpenTerminal()
    }

    @MainActor
    private static func fallbackOpenTerminal() {
        guard
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: terminalBundleIdentifier
            )
        else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
