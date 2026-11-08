// swift-tools-version:6.0
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "vorssaint",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "vorssaint",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/vorssaint",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Vision"),
            ]
        ),
        .testTarget(name: "vorssaintTests", dependencies: ["vorssaint"], path: "Tests"),
    ]
)
