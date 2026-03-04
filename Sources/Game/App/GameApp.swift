import Foundation

struct GameApp {
    private let library: GameContentLibrary
    private let saves: SaveRepository

    init() throws {
        library = try ContentLoader().load()
        saves = SaveRepository()
    }

    func runGraphics(playtestAdventureID: AdventureID? = nil, backend: GraphicsBackend = .native) throws {
        let library = self.library
        let saves = self.saves
        try MainActor.assumeIsolated {
            switch backend {
            case .native:
#if canImport(AppKit)
                GraphicsGameLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID
                )
#else
                try SDLGraphicsLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID
                )
#endif
            case .sdl:
                try SDLGraphicsLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID
                )
            }
        }
    }

    func runEditor() {
        let library = self.library
        MainActor.assumeIsolated {
#if canImport(AppKit)
            AdventureEditorLauncher.run(library: library)
#else
            _ = library
            PlatformRuntimeSupport.writeError("Codexitma editor mode is currently only available in the native macOS frontend.\n")
#endif
        }
    }

    func runScript(commands: [String], emitStepSnapshots: Bool) throws {
        let automation = AutomationSession(library: library, saveRepository: saves)
        try automation.runScript(commands: commands, emitStepSnapshots: emitStepSnapshots)
    }

    func runBridge() throws {
        let automation = AutomationSession(library: library, saveRepository: saves)
        try automation.runBridge()
    }
}
