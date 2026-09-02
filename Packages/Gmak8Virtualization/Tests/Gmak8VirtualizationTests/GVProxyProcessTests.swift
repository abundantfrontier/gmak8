import Foundation
import Testing

@testable import Gmak8Virtualization

struct GVProxyProcessTests {
    @Test func startCreatesSocketsAndRestartHookFires() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let http = root.appending(path: "g.sock")
        let vfkit = root.appending(path: "n.sock")
        let script = root.appending(path: "fake-gvproxy")
        let counter = root.appending(path: "starts")
        try writeFakeGVProxy(at: script, counter: counter)

        let process = GVProxyProcess(
            config: GVProxyProcess.Config(
                executable: script,
                httpSocket: http,
                vfkitSocket: vfkit,
                readyTimeout: 5,
                maximumRestarts: 2,
                backoff: { _ in 0.05 }
            )
        )
        let restarts = RestartBox()
        process.onRestarted = { restarts.increment() }
        try process.start()
        defer { process.stop() }

        #expect(process.isRunning)
        #expect(FileManager.default.fileExists(atPath: UnixgramPath.fileSystemPath(http)))
        #expect(FileManager.default.fileExists(atPath: UnixgramPath.fileSystemPath(vfkit)))

        // First run of the fake helper exits after creating sockets; supervisor should relaunch.
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline && restarts.value < 1 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(restarts.value >= 1)
        #expect(process.restartCount >= 1)
        #expect(process.isRunning)
    }

    @Test func backoffDoublesAndCaps() {
        #expect(GVProxyProcess.restartBackoff(attempt: 1) == 1)
        #expect(GVProxyProcess.restartBackoff(attempt: 2) == 2)
        #expect(GVProxyProcess.restartBackoff(attempt: 3) == 4)
        #expect(GVProxyProcess.restartBackoff(attempt: 10) == 30)
    }
}

private final class RestartBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private func writeFakeGVProxy(at url: URL, counter: URL) throws {
    let script = """
        #!/bin/sh
        set -e
        http=""
        vfkit=""
        prev=""
        for arg in "$@"; do
          if [ "$prev" = "--listen" ]; then
            http="${arg#unix://}"
          fi
          if [ "$prev" = "--listen-vfkit" ]; then
            vfkit="${arg#unixgram://}"
          fi
          prev="$arg"
        done
        [ -n "$http" ] && : > "$http"
        [ -n "$vfkit" ] && : > "$vfkit"
        n=0
        if [ -f "\(UnixgramPath.fileSystemPath(counter))" ]; then
          n=$(cat "\(UnixgramPath.fileSystemPath(counter))")
        fi
        n=$((n + 1))
        echo "$n" > "\(UnixgramPath.fileSystemPath(counter))"
        if [ "$n" -eq 1 ]; then
          sleep 0.4
          exit 1
        fi
        exec sleep 3600
        """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: UnixgramPath.fileSystemPath(url))
}
