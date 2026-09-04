import ArgumentParser
import Gmak8Kit

@main
struct Gmak8: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gmak8",
        abstract: "Control the local gmak8 Kubernetes cluster.",
        version: "gmak8 \(Gmak8Kit.version)",
        subcommands: [Status.self, Start.self, Stop.self, Version.self, Image.self]
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

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start the local cluster."
        )

        func run() throws {
            try EngineClient.submit(.start, socketURL: HostPaths.current().engineSocket)
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop the local cluster."
        )

        func run() throws {
            try EngineClient.submit(.stop, socketURL: HostPaths.current().engineSocket)
        }
    }

    struct Image: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "image",
            abstract: "List, load, and prune node containerd images.",
            subcommands: [List.self, Load.self, Prune.self]
        )
    }
}

extension Gmak8.Image {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List containerd k8s.io images on the node."
        )

        func run() throws {
            let list = try EngineClient.listImages(socketURL: HostPaths.current().engineSocket)
            print(ImageText.renderList(list))
        }
    }

    struct Load: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "load",
            abstract: "Import an OCI or Docker tar into containerd k8s.io."
        )

        @Argument(help: "Path to an image tar on this Mac.")
        var path: String

        func run() throws {
            try ImageLoad.run(path: path, socketURL: HostPaths.current().engineSocket)
        }
    }

    struct Prune: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Prune unused node images."
        )

        func run() throws {
            let list = try EngineClient.pruneImages(socketURL: HostPaths.current().engineSocket)
            print(ImageText.renderList(list))
        }
    }
}
