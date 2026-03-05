import Foundation

struct GameApp {
    private let library: GameContentLibrary
    private let saves: SaveRepository

    init() throws {
        library = try ContentLoader().load()
        saves = SaveRepository()
    }

    func runGraphics(
        playtestAdventureID: AdventureID? = nil,
        backend: GraphicsBackend = .native,
        automationCommands: [String] = []
    ) throws {
        let library = self.library
        let saves = self.saves
        let preferenceStore = graphicsPreferenceStore(forAutomation: !automationCommands.isEmpty)
        try MainActor.assumeIsolated {
            let soundEngine: any GameSoundPlayback = automationCommands.isEmpty
                ? defaultGraphicsSoundEngine()
                : SilentGameSoundEngine.shared
            switch backend {
            case .native:
#if canImport(AppKit)
                try GraphicsGameLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID,
                    preferenceStore: preferenceStore,
                    soundEngine: soundEngine,
                    automationCommands: automationCommands
                )
#else
                try SDLGraphicsLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID,
                    preferenceStore: preferenceStore,
                    soundEngine: soundEngine,
                    automationCommands: automationCommands
                )
#endif
            case .sdl:
                try SDLGraphicsLauncher.run(
                    library: library,
                    saveRepository: saves,
                    playtestAdventureID: playtestAdventureID,
                    preferenceStore: preferenceStore,
                    soundEngine: soundEngine,
                    automationCommands: automationCommands
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

    private func graphicsPreferenceStore(forAutomation enabled: Bool) -> GraphicsPreferenceStore {
        guard enabled else {
            return .shared
        }

        #if os(Windows)
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codexitma-graphics-automation-\(UUID().uuidString)")
            .appendingPathExtension("json")
        return GraphicsPreferenceStore(fileURL: fileURL)
        #else
        let suiteName = "codexitma.graphics.automation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return GraphicsPreferenceStore(defaults: defaults)
        #endif
    }
}
