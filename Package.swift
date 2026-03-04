// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Game",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .systemLibrary(
            name: "CSDL3",
            pkgConfig: "sdl3",
            providers: [
                .brew(["sdl3"]),
                .apt(["libsdl3-dev"]),
            ]
        ),
        .executableTarget(
            name: "Game",
            dependencies: ["CSDL3"],
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
