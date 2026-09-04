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
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.4.0")
    ],
    targets: [
        .target(
            name: "Gmak8Kit",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            resources: [
                .copy("Compatibility/compatibility-matrix.json"),
                .copy("Airgap/k3s-airgap.pin"),
                .copy("Airgap/cosign.pub"),
                .copy("Guest/guest.pin"),
                .copy("KubeVirt/virtctl.pin"),
                .copy("KubeVirt/kubevirt-airgap.pin"),
            ]
        ),
        .testTarget(
            name: "Gmak8KitTests",
            dependencies: ["Gmak8Kit"],
            exclude: [
                "Kubeconfig/Goldens"
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
