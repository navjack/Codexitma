import Foundation

enum GameMode: Codable {
    case title
    case exploration
    case dialogue
    case inventory
    case combat
    case pause
    case gameOver
    case ending
}

enum TileType: String, Codable {
    case floor
    case wall
    case water
    case brush
    case doorLocked
    case doorOpen
    case shrine
    case stairs
    case beacon
}

enum Direction: String, Codable, CaseIterable {
    case up
    case down
    case left
    case right

    var delta: Position {
        switch self {
        case .up: return Position(x: 0, y: -1)
        case .down: return Position(x: 0, y: 1)
        case .left: return Position(x: -1, y: 0)
        case .right: return Position(x: 1, y: 0)
        }
    }
}

enum ActionCommand: Equatable {
    case move(Direction)
    case interact
    case openInventory
    case confirm
    case cancel
    case help
    case save
    case load
    case newGame
    case quit
    case none
}

enum ANSIColor: String, Codable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case reset

    var foregroundCode: String {
        switch self {
        case .black: return "30"
        case .red: return "31"
        case .green: return "32"
        case .yellow: return "33"
        case .blue: return "34"
        case .magenta: return "35"
        case .cyan: return "36"
        case .white: return "37"
        case .brightBlack: return "90"
        case .reset: return "39"
        }
    }
}

struct Position: Codable, Hashable {
    var x: Int
    var y: Int

    static func + (lhs: Position, rhs: Position) -> Position {
        Position(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

struct Tile {
    var type: TileType
    var glyph: Character
    var walkable: Bool
    var color: ANSIColor
}

enum ItemID: String, Codable, CaseIterable {
    case healingTonic
    case ironKey
    case lanternOil
    case charmFragment
    case lensCore
    case shrineKey
}

enum ItemKind: String, Codable {
    case consumable
    case key
    case quest
    case upgrade
}

struct Item: Codable, Equatable {
    let id: ItemID
    let name: String
    let kind: ItemKind
    let value: Int
}

typealias NPCID = String
typealias EnemyID = String

enum AIKind: String, Codable {
    case idle
    case stalk
    case guardian
    case boss
}

enum QuestFlag: String, Codable, Hashable, CaseIterable {
    case metElder
    case southShrineLit
    case orchardShrineLit
    case barrowUnlocked
    case obtainedLensCore
    case fenCrossed
    case beaconLit
    case keeperDefeated
}

struct QuestState: Codable {
    var flags: Set<QuestFlag> = []

    func has(_ flag: QuestFlag) -> Bool {
        flags.contains(flag)
    }

    mutating func set(_ flag: QuestFlag) {
        flags.insert(flag)
    }
}

struct PlayerState: Codable {
    var name: String
    var health: Int
    var maxHealth: Int
    var stamina: Int
    var maxStamina: Int
    var attack: Int
    var defense: Int
    var lanternCharge: Int
    var inventory: [Item]
    var position: Position
    var currentMapID: String
    var lastSavePosition: Position
    var lastSaveMapID: String
}

struct NPCState: Codable {
    let id: NPCID
    var name: String
    var position: Position
    var mapID: String
    var dialogueID: String
    var glyphSymbol: Character
    var glyphColor: ANSIColor
    var dialogueState: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case mapID
        case dialogueID
        case glyphSymbol
        case glyphColor
        case dialogueState
    }

    init(
        id: NPCID,
        name: String,
        position: Position,
        mapID: String,
        dialogueID: String,
        glyphSymbol: Character,
        glyphColor: ANSIColor,
        dialogueState: Int
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.mapID = mapID
        self.dialogueID = dialogueID
        self.glyphSymbol = glyphSymbol
        self.glyphColor = glyphColor
        self.dialogueState = dialogueState
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Position.self, forKey: .position)
        mapID = try container.decode(String.self, forKey: .mapID)
        dialogueID = try container.decode(String.self, forKey: .dialogueID)
        let glyphString = try container.decode(String.self, forKey: .glyphSymbol)
        glyphSymbol = glyphString.first ?? "&"
        glyphColor = try container.decode(ANSIColor.self, forKey: .glyphColor)
        dialogueState = try container.decode(Int.self, forKey: .dialogueState)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        try container.encode(mapID, forKey: .mapID)
        try container.encode(dialogueID, forKey: .dialogueID)
        try container.encode(String(glyphSymbol), forKey: .glyphSymbol)
        try container.encode(glyphColor, forKey: .glyphColor)
        try container.encode(dialogueState, forKey: .dialogueState)
    }
}

struct EnemyState: Codable, Equatable {
    let id: EnemyID
    var name: String
    var position: Position
    var hp: Int
    var maxHP: Int
    var attack: Int
    var defense: Int
    var ai: AIKind
    var glyph: Character
    var color: ANSIColor
    var mapID: String
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case position
        case hp
        case maxHP
        case attack
        case defense
        case ai
        case glyph
        case color
        case mapID
        case active
    }

    init(
        id: EnemyID,
        name: String,
        position: Position,
        hp: Int,
        maxHP: Int,
        attack: Int,
        defense: Int,
        ai: AIKind,
        glyph: Character,
        color: ANSIColor,
        mapID: String,
        active: Bool
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.hp = hp
        self.maxHP = maxHP
        self.attack = attack
        self.defense = defense
        self.ai = ai
        self.glyph = glyph
        self.color = color
        self.mapID = mapID
        self.active = active
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Position.self, forKey: .position)
        hp = try container.decode(Int.self, forKey: .hp)
        maxHP = try container.decode(Int.self, forKey: .maxHP)
        attack = try container.decode(Int.self, forKey: .attack)
        defense = try container.decode(Int.self, forKey: .defense)
        ai = try container.decode(AIKind.self, forKey: .ai)
        let glyphString = try container.decode(String.self, forKey: .glyph)
        glyph = glyphString.first ?? "?"
        color = try container.decode(ANSIColor.self, forKey: .color)
        mapID = try container.decode(String.self, forKey: .mapID)
        active = try container.decode(Bool.self, forKey: .active)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(position, forKey: .position)
        try container.encode(hp, forKey: .hp)
        try container.encode(maxHP, forKey: .maxHP)
        try container.encode(attack, forKey: .attack)
        try container.encode(defense, forKey: .defense)
        try container.encode(ai, forKey: .ai)
        try container.encode(String(glyph), forKey: .glyph)
        try container.encode(color, forKey: .color)
        try container.encode(mapID, forKey: .mapID)
        try container.encode(active, forKey: .active)
    }
}

struct Portal: Codable {
    let from: Position
    let toMap: String
    let toPosition: Position
    let requiredFlag: QuestFlag?
    let blockedMessage: String?
}

enum InteractableKind: String, Codable {
    case npc
    case shrine
    case chest
    case bed
    case gate
    case beacon
}

struct InteractableDefinition: Codable {
    let id: String
    let kind: InteractableKind
    let position: Position
    let title: String
    let lines: [String]
    let rewardItem: ItemID?
    let requiredFlag: QuestFlag?
    let grantsFlag: QuestFlag?
}

struct MapDefinition: Codable {
    let id: String
    let name: String
    let layoutFile: String
    let lines: [String]
    let spawn: Position
    let portals: [Portal]
    let interactables: [InteractableDefinition]
}

struct DialogueNode: Codable {
    let id: String
    let speaker: String
    let lines: [String]
}

struct EncounterDefinition: Codable {
    let id: String
    let enemyID: String
    let introLine: String
}

struct WorldState: Codable {
    var maps: [String: MapDefinition]
    var npcs: [NPCState]
    var enemies: [EnemyState]
    var openedInteractables: Set<String>
}

struct SaveGame: Codable {
    var player: PlayerState
    var world: WorldState
    var quests: QuestState
    var playTimeSeconds: Int
}

struct GameContent: @unchecked Sendable {
    let maps: [String: MapDefinition]
    let dialogues: [String: DialogueNode]
    let encounters: [String: EncounterDefinition]
    let items: [ItemID: Item]
    let initialNPCs: [NPCState]
    let initialEnemies: [EnemyState]
}

struct ScreenCell: Equatable {
    var character: Character
    var color: ANSIColor
}

struct ScreenBuffer {
    let width: Int
    let height: Int
    private(set) var cells: [ScreenCell]

    init(width: Int = 80, height: Int = 24, fill: Character = " ") {
        self.width = width
        self.height = height
        self.cells = Array(
            repeating: ScreenCell(character: fill, color: .reset),
            count: width * height
        )
    }

    mutating func put(_ char: Character, color: ANSIColor = .reset, x: Int, y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        cells[(y * width) + x] = ScreenCell(character: char, color: color)
    }

    mutating func write(_ text: String, color: ANSIColor = .reset, x: Int, y: Int, maxWidth: Int? = nil) {
        let limit = maxWidth ?? width - x
        guard limit > 0 else { return }
        for (index, char) in text.prefix(limit).enumerated() {
            put(char, color: color, x: x + index, y: y)
        }
    }

    func line(_ y: Int) -> String {
        guard y >= 0, y < height else { return "" }
        let start = y * width
        let end = start + width
        return String(cells[start..<end].map(\.character))
    }
}

protocol RenderableEntity {
    var position: Position { get }
    var glyph: Character { get }
    var color: ANSIColor { get }
}

protocol Scene {
    func render(into: inout ScreenBuffer, state: GameState)
    mutating func handle(_ command: ActionCommand, engine: inout GameEngine)
}

struct GameState {
    var mode: GameMode = .title
    var player: PlayerState
    var world: WorldState
    var quests: QuestState
    var messages: [String]
    var currentDialogue: DialogueNode?
    var shouldQuit = false
    var playTimeSeconds = 0

    mutating func log(_ message: String) {
        messages.append(message)
        if messages.count > 8 {
            messages.removeFirst(messages.count - 8)
        }
    }
}

extension EnemyState: RenderableEntity {}

extension NPCState: RenderableEntity {
    var glyph: Character { glyphSymbol }
    var color: ANSIColor { glyphColor }
}
