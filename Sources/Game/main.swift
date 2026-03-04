import Foundation

do {
    let app = try GameApp()
    let options = try LaunchOptions.parse(arguments: CommandLine.arguments)
    switch options.target {
    case .interactive(let mode):
        switch mode {
        case .graphics:
            try app.runGraphics(
                playtestAdventureID: options.playtestAdventureID,
                backend: options.graphicsBackend
            )
        case .terminal:
            try app.runTerminal()
        }
    case .editor:
        app.runEditor()
    case .script:
        try app.runScript(commands: options.commands, emitStepSnapshots: options.emitStepSnapshots)
    case .bridge:
        try app.runBridge()
    }
} catch {
    fputs("Codexitma failed to start: \(error)\n", stderr)
    exit(1)
}
