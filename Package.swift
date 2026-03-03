// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Game",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Game",
            resources: [
                .process("ContentData"),
            ]
        ),
        .testTarget(
            name: "GameTests",
            dependencies: ["Game"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
