// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gmak8XPC",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gmak8XPC",
            targets: ["Gmak8XPC"]
        )
    ],
    targets: [
        .target(
            name: "Gmak8XPC"
        ),
        .testTarget(
            name: "Gmak8XPCTests",
            dependencies: ["Gmak8XPC"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
