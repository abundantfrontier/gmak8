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
    dependencies: [
        .package(path: "../Gmak8Kit"),
        .package(path: "../Gmak8GuestClient"),
    ],
    targets: [
        .target(
            name: "Gmak8XPC",
            dependencies: [
                .product(name: "Gmak8Kit", package: "Gmak8Kit"),
                .product(name: "Gmak8GuestClient", package: "Gmak8GuestClient"),
            ]
        ),
        .testTarget(
            name: "Gmak8XPCTests",
            dependencies: [
                "Gmak8XPC",
                .product(name: "Gmak8Kit", package: "Gmak8Kit"),
                .product(name: "Gmak8GuestClient", package: "Gmak8GuestClient"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
