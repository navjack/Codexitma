import Foundation

struct GameApp {
    private let content: GameContent
    private let renderer: TerminalRenderer
    private let input: InputReader
    private let saves: SaveRepository

    init() throws {
        content = try ContentLoader().load()
        renderer = TerminalRenderer()
        input = InputReader()
        saves = SaveRepository()
    }

    func runTerminal() throws {
        let engine = GameEngine(content: content, saveRepository: saves)
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
        let content = self.content
        let saves = self.saves
        MainActor.assumeIsolated {
            GraphicsGameLauncher.run(content: content, saveRepository: saves)
        }
    }

    func runScript(commands: [String], emitStepSnapshots: Bool) throws {
        let automation = AutomationSession(content: content, saveRepository: saves)
        try automation.runScript(commands: commands, emitStepSnapshots: emitStepSnapshots)
    }

    func runBridge() throws {
        let automation = AutomationSession(content: content, saveRepository: saves)
        try automation.runBridge()
    }
}
