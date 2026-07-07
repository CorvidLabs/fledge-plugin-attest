// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "fledge-plugin-attest",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "fledge-attest", targets: ["fledge-attest"])
    ],
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/attest.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "fledge-attest",
            dependencies: [
                .product(name: "AttestKit", package: "attest"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "fledge-attestTests",
            dependencies: ["fledge-attest"]
        )
    ]
)
