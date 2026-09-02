import Foundation
import Testing

@testable import Gmak8XPC

struct DiagnosticsArchiveTests {
    @Test func zipRedactsTokensAndPasswords() throws {
        let request = DiagnosticsArchiveRequest(
            settingsJSON: #"{"password":"s3cret","token":"tok_live_abc","clusterName":"gmak8"}"#,
            engineLog: "Authorization: Bearer super-secret-token\npassword=hunter2\ncluster ok\n",
            serialLog: "user token: aabbccdd\n",
            kubectlNodes: "Ready",
            kubectlPods: "token: pod-secret-value",
            versions: "gmak8 0.0.1\n",
            kubeconfig: """
                users:
                - name: gmak8
                  user:
                    token: REALTOKEN
                    client-key-data: KEYDATA
                """,
            includeCredentials: false
        )
        let files = DiagnosticsArchive.files(from: request)
        let settings = string(files["settings.json"])
        let engine = string(files["engine.log"])
        let serial = string(files["serial.log"])
        let pods = string(files["kubectl-pods.txt"])
        #expect(settings.contains("gmak8"))
        #expect(settings.contains(SecretRedactor.placeholder))
        #expect(!settings.contains("s3cret"))
        #expect(!settings.contains("tok_live_abc"))
        #expect(!engine.contains("super-secret-token"))
        #expect(!engine.contains("hunter2"))
        #expect(engine.contains("cluster ok"))
        #expect(!serial.contains("aabbccdd"))
        #expect(!pods.contains("pod-secret-value"))
        #expect(files["kubeconfig"] == nil)

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "gmak8-diag-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let zipURL = directory.appending(path: "gmak8-diagnostics.zip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try DiagnosticsArchive.writeZip(files: files, to: zipURL)
        let zipBytes = try Data(contentsOf: zipURL)
        #expect(zipBytes.starts(with: [0x50, 0x4b, 0x03, 0x04]))
        let zipText = String(decoding: zipBytes, as: UTF8.self)
        #expect(zipText.contains(SecretRedactor.placeholder))
        #expect(!zipText.contains("s3cret"))
        #expect(!zipText.contains("tok_live_abc"))
        #expect(!zipText.contains("super-secret-token"))
        #expect(!zipText.contains("hunter2"))
        #expect(!zipText.contains("REALTOKEN"))
        #expect(!zipText.contains("KEYDATA"))
        #expect(zipText.contains("gmak8"))
    }

    @Test func zipIncludesKubeconfigOnlyWhenCredentialsOptedIn() {
        let kubeconfig = "token: REALTOKEN\n"
        let omitted = DiagnosticsArchive.files(
            from: DiagnosticsArchiveRequest(
                settingsJSON: "{}",
                engineLog: "ok",
                serialLog: "",
                versions: "gmak8\n",
                kubeconfig: kubeconfig,
                includeCredentials: false
            )
        )
        #expect(omitted["kubeconfig"] == nil)
        let included = DiagnosticsArchive.files(
            from: DiagnosticsArchiveRequest(
                settingsJSON: "{}",
                engineLog: "password=hunter2",
                serialLog: "",
                versions: "gmak8\n",
                kubeconfig: kubeconfig,
                includeCredentials: true
            )
        )
        #expect(string(included["kubeconfig"]) == kubeconfig)
        #expect(!string(included["engine.log"]).contains("hunter2"))
    }

    private func string(_ data: Data?) -> String {
        String(data: data ?? Data(), encoding: .utf8) ?? ""
    }
}
