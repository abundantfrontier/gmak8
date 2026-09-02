// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gmak8Virtualization",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gmak8Virtualization",
            targets: ["Gmak8Virtualization"]
        )
    ],
    targets: [
        .target(
            name: "Gmak8Virtualization"
        ),
        .testTarget(
            name: "Gmak8VirtualizationTests",
            dependencies: ["Gmak8Virtualization"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
