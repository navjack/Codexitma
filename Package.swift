// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let supportedPlatforms: [SupportedPlatform]? = {
#if os(macOS)
    return [
        .macOS(.v14),
    ]
#else
    return nil
#endif
}()

let package = Package(
    name: "Game",
    platforms: supportedPlatforms,
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
            ],
            linkerSettings: [
                .linkedLibrary("SDL3", .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "GameTests",
            dependencies: ["Game"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
