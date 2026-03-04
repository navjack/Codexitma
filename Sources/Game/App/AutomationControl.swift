import Foundation

enum LaunchTarget: Equatable {
    case interactive(LaunchMode)
    case editor
    case script
    case bridge
}

enum AutomationError: Error, CustomStringConvertible {
    case missingFlagValue(String)
    case invalidCommand(String)

    var description: String {
        switch self {
        case .missingFlagValue(let flag):
            return "Missing value for \(flag)"
        case .invalidCommand(let token):
            return "Invalid automation command: \(token)"
        }
    }
}

struct LaunchOptions: Equatable {
    let target: LaunchTarget
    let graphicsBackend: GraphicsBackend
    let commands: [String]
    let emitStepSnapshots: Bool
    let playtestAdventureID: AdventureID?

    static func parse(arguments: [String]) throws -> LaunchOptions {
        var target: LaunchTarget = .interactive(LaunchMode.parse(arguments: arguments))
        var graphicsBackend: GraphicsBackend = .native
        var commands: [String] = []
        var emitStepSnapshots = false
        var playtestAdventureID: AdventureID?

        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--terminal":
                target = .interactive(.terminal)
            case "--graphics":
                target = .interactive(.graphics)
                graphicsBackend = .native
            case "--sdl":
                target = .interactive(.graphics)
                graphicsBackend = .sdl
            case "--editor":
                target = .editor
            case "--bridge":
                target = .bridge
            case "--playtest":
                guard index + 1 < arguments.count else {
                    throw AutomationError.missingFlagValue("--playtest")
                }
                playtestAdventureID = AdventureID(rawValue: arguments[index + 1])
                index += 1
            case "--step-json":
                emitStepSnapshots = true
            case "--script":
                guard index + 1 < arguments.count else {
                    throw AutomationError.missingFlagValue("--script")
                }
                target = .script
                commands.append(contentsOf: AutomationTokenizer.tokens(from: arguments[index + 1]))
                index += 1
            case "--script-file":
                guard index + 1 < arguments.count else {
                    throw AutomationError.missingFlagValue("--script-file")
                }
                target = .script
                let path = arguments[index + 1]
                let raw = try String(contentsOfFile: path)
                commands.append(contentsOf: AutomationTokenizer.tokens(from: raw))
                index += 1
            default:
                break
            }
            index += 1
        }

        return LaunchOptions(
            target: target,
            graphicsBackend: graphicsBackend,
            commands: commands,
            emitStepSnapshots: emitStepSnapshots,
            playtestAdventureID: playtestAdventureID
        )
    }
}

enum AutomationDirective: Equatable {
    case game(ActionCommand)
    case snapshot
    case reset
}

enum AutomationTokenizer {
    static func tokens(from raw: String) -> [String] {
        raw
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                let trimmed = line.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
                return trimmed.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).map(String.init)
            }
            .filter { !$0.isEmpty }
    }
}

enum AutomationCommandParser {
    static func parse(_ token: String) throws -> AutomationDirective {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "state", "snapshot":
            return .snapshot
        case "reset":
            return .reset
        case "up", "north", "w":
            return .game(.move(.up))
        case "down", "south", "s":
            return .game(.move(.down))
        case "left", "west", "a":
            return .game(.move(.left))
        case "right", "east", "d":
            return .game(.move(.right))
        case "turnleft", "turn-left", "rotateleft", "tl":
            return .game(.turnLeft)
        case "turnright", "turn-right", "rotateright", "tr":
            return .game(.turnRight)
        case "backward", "backstep", "stepback", "reverse", "retreat":
            return .game(.moveBackward)
        case "interact", "act", "talk", "use", "e", "space", "confirm":
            return .game(.interact)
        case "inventory", "item", "pack", "i":
            return .game(.openInventory)
        case "drop", "discard", "trash", "r":
            return .game(.dropInventoryItem)
        case "help", "hint", "goal", "j", "h":
            return .game(.help)
        case "save", "k":
            return .game(.save)
        case "load", "l":
            return .game(.load)
        case "new", "newgame", "n":
            return .game(.newGame)
        case "back", "cancel", "q", "esc":
            return .game(.cancel)
        case "quit", "exit", "x":
            return .game(.quit)
        default:
            throw AutomationError.invalidCommand(token)
        }
    }
}

struct AutomationSnapshot: Codable {
    let adventureID: String
    let mode: String
    let mapID: String
    let mapName: String
    let facing: String
    let position: Position
    let health: Int
    let maxHealth: Int
    let stamina: Int
    let lanternCharge: Int
    let marks: Int
    let inventory: [String]
    let questFlags: [String]
    let openedInteractables: [String]
    let activeSwitchSequence: [String]
    let activeEnemies: [String]
    let objective: String
    let lastMessage: String?
    let dialogueSpeaker: String?
    let shopTitle: String?
    let shopOffers: [String]
    let shouldQuit: Bool

    static func from(state: GameState) -> AutomationSnapshot {
        AutomationSnapshot(
            adventureID: state.currentAdventureID.rawValue,
            mode: String(describing: state.mode),
            mapID: state.player.currentMapID,
            mapName: state.world.maps[state.player.currentMapID]?.name ?? state.player.currentMapID,
            facing: state.player.facing.rawValue,
            position: state.player.position,
            health: state.player.health,
            maxHealth: state.player.maxHealth,
            stamina: state.player.stamina,
            lanternCharge: state.player.lanternCharge,
            marks: state.player.marks,
            inventory: state.player.inventory.map(\.name),
            questFlags: state.quests.flags.map(\.rawValue).sorted(),
            openedInteractables: state.world.openedInteractables.sorted(),
            activeSwitchSequence: state.world.activeSwitchSequence,
            activeEnemies: state.world.enemies
                .filter { $0.active }
                .map(\.id)
                .sorted(),
            objective: QuestSystem.objective(for: state.quests, flow: state.questFlow),
            lastMessage: state.messages.last,
            dialogueSpeaker: state.currentDialogue?.speaker,
            shopTitle: state.shopTitle,
            shopOffers: state.shopOffers.map {
                let itemName = itemTable[$0.itemID]?.name ?? $0.itemID.rawValue
                let soldOut = !$0.repeatable && state.world.purchasedShopOffers.contains($0.id)
                return soldOut ? "\(itemName) [SOLD]" : "\(itemName) [\($0.price)M]"
            },
            shouldQuit: state.shouldQuit
        )
    }
}

struct AutomationResponse: Codable {
    let ok: Bool
    let token: String
    let snapshot: AutomationSnapshot?
    let error: String?
}

final class AutomationSession {
    private let library: GameContentLibrary
    private let saveRepository: SaveRepository
    private var engine: GameEngine
    private let encoder: JSONEncoder

    init(library: GameContentLibrary, saveRepository: SaveRepository) {
        self.library = library
        self.saveRepository = saveRepository
        self.engine = GameEngine(library: library, saveRepository: saveRepository)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func runScript(commands: [String], emitStepSnapshots: Bool) throws {
        if commands.isEmpty {
            emit(token: "state", snapshot: AutomationSnapshot.from(state: engine.state))
            return
        }

        for token in commands {
            let directive = try AutomationCommandParser.parse(token)
            try apply(directive, token: token, emitSnapshot: emitStepSnapshots)
        }

        emit(token: "final", snapshot: AutomationSnapshot.from(state: engine.state))
    }

    func runBridge() throws {
        emit(token: "ready", snapshot: AutomationSnapshot.from(state: engine.state))

        while let line = readLine() {
            let tokens = AutomationTokenizer.tokens(from: line)
            if tokens.isEmpty { continue }

            for token in tokens {
                do {
                    let directive = try AutomationCommandParser.parse(token)
                    try apply(directive, token: token, emitSnapshot: true)
                } catch {
                    emitError(token: token, message: String(describing: error))
                }
            }
        }
    }

    private func apply(_ directive: AutomationDirective, token: String, emitSnapshot: Bool) throws {
        switch directive {
        case .snapshot:
            emit(token: token, snapshot: AutomationSnapshot.from(state: engine.state))
        case .reset:
            engine = GameEngine(library: library, saveRepository: saveRepository)
            emit(token: token, snapshot: AutomationSnapshot.from(state: engine.state))
        case .game(let command):
            engine.handle(command)
            if emitSnapshot {
                emit(token: token, snapshot: AutomationSnapshot.from(state: engine.state))
            }
        }
    }

    private func emit(token: String, snapshot: AutomationSnapshot) {
        let response = AutomationResponse(ok: true, token: token, snapshot: snapshot, error: nil)
        output(response)
    }

    private func emitError(token: String, message: String) {
        let response = AutomationResponse(ok: false, token: token, snapshot: nil, error: message)
        output(response)
    }

    private func output(_ response: AutomationResponse) {
        guard let data = try? encoder.encode(response),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        print(line)
        fflush(stdout)
    }
}
