import ArgumentParser
import Gmak8Kit

@main
struct Gmak8: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gmak8",
        abstract: "Control the local gmak8 Kubernetes cluster.",
        version: "gmak8 \(Gmak8Kit.version)",
        subcommands: [Status.self, Version.self]
    )
}

extension Gmak8 {
    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the gmak8 version."
        )

        func run() {
            print("gmak8 \(Gmak8Kit.version)")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print cluster status from gmak8-core."
        )

        func run() throws {
            let status = try EngineClient.status(socketURL: HostPaths.current().engineSocket)
            print(StatusText.render(status))
        }
    }
}
