import Foundation

enum GraphicsAutomationError: Error, CustomStringConvertible {
    case invalidCommand(String)

    var description: String {
        switch self {
        case .invalidCommand(let token):
            return "Invalid graphics automation command: \(token)"
        }
    }
}

enum GraphicsAutomationDirective: Equatable {
    case game(ActionCommand)
    case warp(mapID: String?, position: Position, facing: Direction?)
    case cycleTheme
    case selectTheme(GraphicsVisualTheme)
    case toggleDebugLighting
    case screenshot(String?)
}

enum GraphicsAutomationCommandParser {
    static func parse(_ token: String) throws -> GraphicsAutomationDirective {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if let screenshot = parseScreenshotDirective(token: trimmed) {
            return screenshot
        }

        if let theme = parseThemeDirective(token: trimmed) {
            return theme
        }

        switch trimmed.lowercased() {
        case "theme", "style", "t":
            return .cycleTheme
        case "debug", "dbg", "f10":
            return .toggleDebugLighting
        default:
            break
        }

        switch try AutomationCommandParser.parse(trimmed) {
        case .game(let command):
            return .game(command)
        case .warp(let mapID, let position, let facing):
            return .warp(mapID: mapID, position: position, facing: facing)
        default:
            throw GraphicsAutomationError.invalidCommand(token)
        }
    }

    private static func parseScreenshotDirective(token: String) -> GraphicsAutomationDirective? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let verb = parts.first?.lowercased(),
              ["shot", "screenshot", "capture", "f12"].contains(verb) else {
            return nil
        }

        if parts.count == 2, !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .screenshot(parts[1])
        }

        return .screenshot(nil)
    }

    private static func parseThemeDirective(token: String) -> GraphicsAutomationDirective? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let verb = parts.first?.lowercased(),
              ["theme", "style"].contains(verb),
              parts.count == 2 else {
            return nil
        }

        guard let theme = graphicsTheme(from: parts[1]) else {
            return nil
        }

        return .selectTheme(theme)
    }

    private static func graphicsTheme(from token: String) -> GraphicsVisualTheme? {
        let normalized = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch normalized {
        case "gemstone":
            return .gemstone
        case "ultima":
            return .ultima
        case "depth", "depth3d", "3d":
            return .depth3D
        default:
            return nil
        }
    }
}

@MainActor
final class GraphicsAutomationRunner {
    private let directives: [GraphicsAutomationDirective]
    private var index = 0

    init(tokens: [String]) throws {
        directives = try tokens.map(GraphicsAutomationCommandParser.parse)
    }

    var isFinished: Bool {
        index >= directives.count
    }

    func step(
        sendCommand: (ActionCommand) -> Void,
        warpPlayer: (String?, Position, Direction?) throws -> Void,
        cycleTheme: () -> Void,
        selectTheme: (GraphicsVisualTheme) -> Void,
        toggleDebugLighting: () -> Void,
        captureScreenshot: (String?) -> Void
    ) throws {
        guard !isFinished else {
            return
        }

        let directive = directives[index]
        index += 1

        switch directive {
        case .game(let command):
            sendCommand(command)
        case .warp(let mapID, let position, let facing):
            try warpPlayer(mapID, position, facing)
        case .cycleTheme:
            cycleTheme()
        case .selectTheme(let theme):
            selectTheme(theme)
        case .toggleDebugLighting:
            toggleDebugLighting()
        case .screenshot(let label):
            captureScreenshot(label)
        }
    }
}
