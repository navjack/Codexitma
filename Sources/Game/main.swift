import Foundation

do {
    let app = try GameApp()
    let options = try LaunchOptions.parse(arguments: CommandLine.arguments)
    switch options.target {
    case .interactive:
        try app.runGraphics(
            playtestAdventureID: options.playtestAdventureID,
            backend: options.graphicsBackend
        )
    case .graphicsScript:
        try app.runGraphics(
            playtestAdventureID: options.playtestAdventureID,
            backend: options.graphicsBackend,
            automationCommands: options.commands
        )
    case .editor:
        app.runEditor()
    case .script:
        try app.runScript(commands: options.commands, emitStepSnapshots: options.emitStepSnapshots)
    case .bridge:
        try app.runBridge()
    }
} catch {
    PlatformRuntimeSupport.writeError("Codexitma failed to start: \(error)\n")
    PlatformRuntimeSupport.exitFailure()
}
