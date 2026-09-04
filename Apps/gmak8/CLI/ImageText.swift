import Foundation
import Gmak8XPC

enum ImageText {
    static func renderList(_ list: NodeImageList) -> String {
        if list.items.isEmpty {
            return "No node images."
        }
        return list.items.map { image in
            let name = image.displayName
            let size = formatBytes(image.sizeBytes)
            let kind = image.system ? " system" : ""
            return "\(name)  \(image.id)  \(size)\(kind)"
        }.joined(separator: "\n")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kib = Double(bytes) / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.1f MiB", mib)
        }
        return String(format: "%.1f GiB", mib / 1024)
    }
}

enum ImageLoad {
    static func run(path: String, socketURL: URL) throws {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
        let wait = ImageLoadWait()
        let subscription = try EngineClient.subscribe(
            socketURL: socketURL,
            onEvent: { event in
                wait.handle(event)
            },
            onError: { error in
                wait.fail(error)
            }
        )
        defer { subscription.cancel() }
        try EngineClient.submit(.loadImage(path: resolved), socketURL: socketURL)
        wait.group.wait()
        if let waitError = wait.error {
            throw waitError
        }
        if let error = wait.status?.lastError, !error.isEmpty {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            throw CLIError.engineError(.invalidRequest)
        }
        if let imported = wait.importedLine {
            print(imported)
        } else {
            print("imported")
        }
    }
}

final class ImageLoadWait: @unchecked Sendable {
    let group = DispatchGroup()
    private let lock = NSLock()
    private var sawJob = false
    private var finished = false
    private var lastStatus: EngineStatus?
    private var imported: String?
    private var waitError: CLIError?

    init() {
        group.enter()
    }

    var status: EngineStatus? {
        lock.lock()
        defer { lock.unlock() }
        return lastStatus
    }

    var importedLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return imported
    }

    var error: CLIError? {
        lock.lock()
        defer { lock.unlock() }
        return waitError
    }

    func handle(_ event: EngineEvent) {
        lock.lock()
        switch event {
        case .status(let status):
            lastStatus = status
            if status.imageJob != nil {
                sawJob = true
            }
            let done = sawJob && status.imageJob == nil
            if done && !finished {
                finished = true
                lock.unlock()
                group.leave()
                return
            }
        case .log(_, let line):
            if line.hasPrefix("imported") {
                imported = line
                if !finished {
                    finished = true
                    lock.unlock()
                    group.leave()
                    return
                }
            }
        case .images:
            break
        }
        lock.unlock()
    }

    func fail(_ error: CLIError) {
        lock.lock()
        waitError = error
        if !finished {
            finished = true
            lock.unlock()
            group.leave()
            return
        }
        lock.unlock()
    }
}
