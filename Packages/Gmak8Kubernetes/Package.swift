// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gmak8Kubernetes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gmak8Kubernetes",
            targets: ["Gmak8Kubernetes"]
        )
    ],
    dependencies: [
        .package(path: "../Gmak8Kit"),
        .package(url: "https://github.com/swiftkube/client.git", from: "0.25.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.86.2"),
    ],
    targets: [
        .target(
            name: "Gmak8Kubernetes",
            dependencies: [
                .product(name: "Gmak8Kit", package: "Gmak8Kit"),
                .product(name: "SwiftkubeClient", package: "client"),
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "Gmak8KubernetesTests",
            dependencies: [
                "Gmak8Kubernetes",
                .product(name: "Gmak8Kit", package: "Gmak8Kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
