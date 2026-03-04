import Foundation

enum GraphicsVisualTheme: String, CaseIterable, Equatable {
    case gemstone
    case ultima
    case depth3D

    var displayName: String {
        switch self {
        case .gemstone:
            return "Gemstone"
        case .ultima:
            return "Ultima"
        case .depth3D:
            return "Depth 3D"
        }
    }

    var summary: String {
        switch self {
        case .gemstone:
            return "Bright chamber borders, black void framing, and chunkier sprites."
        case .ultima:
            return "Cleaner overworld boards with flatter tiles and a stricter classic field look."
        case .depth3D:
            return "A first-person pseudo-3D dungeon view that reads the same live map."
        }
    }

    func next() -> GraphicsVisualTheme {
        switch self {
        case .gemstone:
            return .ultima
        case .ultima:
            return .depth3D
        case .depth3D:
            return .gemstone
        }
    }
}

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

enum GameSoundCue {
    case introMusic
    case walk
    case attack
    case useItem
    case menuConfirm
}

@MainActor
protocol GameSoundPlayback {
    func play(_ cue: GameSoundCue)
}

@MainActor
final class SilentGameSoundEngine: GameSoundPlayback {
    static let shared = SilentGameSoundEngine()

    func play(_ cue: GameSoundCue) {
        _ = cue
    }
}

@MainActor
func defaultGraphicsSoundEngine() -> any GameSoundPlayback {
#if canImport(AVFoundation)
    AppleIISoundEngine.shared
#else
    SilentGameSoundEngine.shared
#endif
}
