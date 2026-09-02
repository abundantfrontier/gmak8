// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Gmak8GuestClient",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Gmak8GuestClient",
            targets: ["Gmak8GuestClient"]
        )
    ],
    targets: [
        .target(
            name: "Gmak8GuestClient"
        ),
        .testTarget(
            name: "Gmak8GuestClientTests",
            dependencies: ["Gmak8GuestClient"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
