// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HalbestundeApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "HalbestundeApp",
            targets: ["HalbestundeApp"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HalbestundeApp",
            dependencies: [],
            path: "Sources/HalbestundeApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HalbestundeAppTests",
            dependencies: ["HalbestundeApp"],
            path: "Tests/HalbestundeAppTests"
        ),
    ]
)
