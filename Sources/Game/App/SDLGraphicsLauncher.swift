import Foundation

enum GraphicsBackend: String, Equatable {
    case native
    case sdl

    var displayName: String {
        switch self {
        case .native:
            return "Native"
        case .sdl:
            return "SDL"
        }
    }
}

enum GraphicsBackendError: Error, CustomStringConvertible {
    case sdlUnavailable

    var description: String {
        switch self {
        case .sdlUnavailable:
            return """
            The SDL graphics backend is not linked yet on this branch.
            The cross-platform seam is in progress, but the native AppKit renderer is still the only working graphical frontend.
            """
        }
    }
}

@MainActor
enum SDLGraphicsLauncher {
    static func run(
        library _: GameContentLibrary,
        saveRepository _: SaveRepository,
        playtestAdventureID _: AdventureID? = nil
    ) throws {
        throw GraphicsBackendError.sdlUnavailable
    }
}
