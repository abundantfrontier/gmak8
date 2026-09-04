import AppKit
import Foundation
import Gmak8Kit
import Gmak8Kubernetes

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

    static let execShells = ["/bin/sh", "/bin/bash", "/bin/ash"]

    static func kubectlExecArgs(namespace: String, pod: String, container: String?) -> String {
        var args = "-n \(shellQuoted(namespace)) \(shellQuoted(pod))"
        if let container, !container.isEmpty {
            args += " -c \(shellQuoted(container))"
        }
        return args
    }

    static func execCommand(kubeconfigPath: String, namespace: String, pod: String, container: String?)
        -> String
    {
        let args = kubectlExecArgs(namespace: namespace, pod: pod, container: container)
        let podArgs = kubectlExecArgs(namespace: namespace, pod: pod, container: nil)
        var steps = ["export KUBECONFIG=\(shellQuoted(kubeconfigPath))"]
        steps.append(
            "phase=$(kubectl get pod \(podArgs) -o jsonpath='{.status.phase}' 2>/dev/null); if [ \"$phase\" != \"Running\" ]; then echo \(shellQuoted(WorkloadsCopy.podNotRunning)); exit 0; fi"
        )
        for shell in execShells {
            let quoted = shellQuoted(shell)
            steps.append(
                "if kubectl exec \(args) -- \(quoted) -c 'exit 0' >/dev/null 2>&1; then exec kubectl exec -it \(args) -- \(quoted); fi"
            )
        }
        steps.append("echo \(shellQuoted(WorkloadsCopy.noShell))")
        return steps.joined(separator: "; ")
    }

    static func portForwardCommand(
        kubeconfigPath: String,
        namespace: String,
        pod: String,
        local: Int,
        remote: Int
    ) -> String {
        "export KUBECONFIG=\(shellQuoted(kubeconfigPath)) && kubectl port-forward --address 127.0.0.1 -n \(shellQuoted(namespace)) \(shellQuoted("pod/\(pod)")) \(local):\(remote)"
    }

    @MainActor
    static func openExec(
        namespace: String,
        pod: String,
        container: String?,
        kubeconfig: URL = HostPaths.current().kubeconfigFile
    ) {
        runAppleScript(
            appleScriptSource(
                command: execCommand(
                    kubeconfigPath: kubeconfig.path(percentEncoded: false),
                    namespace: namespace,
                    pod: pod,
                    container: container
                )
            )
        )
    }

    @MainActor
    static func openPortForward(
        namespace: String,
        pod: String,
        local: Int,
        remote: Int,
        kubeconfig: URL = HostPaths.current().kubeconfigFile
    ) {
        runAppleScript(
            appleScriptSource(
                command: portForwardCommand(
                    kubeconfigPath: kubeconfig.path(percentEncoded: false),
                    namespace: namespace,
                    pod: pod,
                    local: local,
                    remote: remote
                )
            )
        )
    }

    static func appleScriptSource(command: String) -> String {
        let quoted = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"",
            with: "\\\""
        )
        return """
            tell application "Terminal"
                activate
                do script "\(quoted)"
            end tell
            """
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
