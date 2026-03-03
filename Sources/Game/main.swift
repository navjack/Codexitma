import Foundation

do {
    let app = try GameApp()
    switch LaunchMode.parse(arguments: CommandLine.arguments) {
    case .graphics:
        app.runGraphics()
    case .terminal:
        try app.runTerminal()
    }
} catch {
    fputs("Ashes of Merrow failed to start: \(error)\n", stderr)
    exit(1)
}
