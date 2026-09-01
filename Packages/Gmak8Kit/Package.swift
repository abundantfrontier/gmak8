// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gmak8Kit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gmak8Kit",
            targets: ["Gmak8Kit"]
        )
    ],
    targets: [
        .target(
            name: "Gmak8Kit"
        ),
        .testTarget(
            name: "Gmak8KitTests",
            dependencies: ["Gmak8Kit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
