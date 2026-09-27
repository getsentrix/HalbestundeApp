// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PianoGlass",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PianoGlass",
            targets: ["PianoGlass"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "PianoGlass",
            dependencies: [],
            path: "Sources/PianoGlass",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PianoGlassTests",
            dependencies: ["PianoGlass"],
            path: "Tests/PianoGlassTests"
        ),
    ]
)
