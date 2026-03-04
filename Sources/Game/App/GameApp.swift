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

    func runGraphics() {
        let library = self.library
        let saves = self.saves
        MainActor.assumeIsolated {
            GraphicsGameLauncher.run(library: library, saveRepository: saves)
        }
    }

    func runEditor() {
        let library = self.library
        MainActor.assumeIsolated {
            AdventureEditorLauncher.run(library: library)
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
