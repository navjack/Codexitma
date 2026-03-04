import Foundation

struct GameApp {
    private let library: GameContentLibrary
    private let renderer: TerminalRenderer
    private let input: InputReader
    private let saves: SaveRepository

    init() throws {
        library = try ContentLoader().load()
        renderer = TerminalRenderer()
        input = InputReader()
        saves = SaveRepository()
    }

    func runTerminal() throws {
        let engine = GameEngine(library: library, saveRepository: saves)
        renderer.prepare()
        defer { renderer.restore() }

        if renderer.isInteractive {
            try input.beginCapture()
        }
        defer { input.endCapture() }

        while !engine.shouldQuit {
            let frame = renderer.makeFrame(for: engine.state)
            renderer.render(frame)

            guard let command = input.readCommand(mode: engine.state.mode) else {
                engine.state.log("Input ended. Leaving Merrow to its silence.")
                break
            }
            engine.handle(command)
        }

        renderer.render(renderer.makeShutdownFrame(message: "The embers dim. Farewell, wanderer."))
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
            fputs("Codexitma editor mode is currently only available in the native macOS frontend.\n", stderr)
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
