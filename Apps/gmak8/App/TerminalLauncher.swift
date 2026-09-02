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

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    @MainActor
    static func open(kubeconfig: URL = HostPaths.current().kubeconfigFile) {
        let source = appleScriptSource(kubeconfigPath: kubeconfig.path(percentEncoded: false))
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
