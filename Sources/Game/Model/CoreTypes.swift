import Foundation

enum GameMode: Codable {
    case title
    case characterCreation
    case exploration
    case dialogue
    case inventory
    case shop
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

    var leftTurn: Direction {
        switch self {
        case .up: return .left
        case .left: return .down
        case .down: return .right
        case .right: return .up
        }
    }

    var rightTurn: Direction {
        switch self {
        case .up: return .right
        case .right: return .down
        case .down: return .left
        case .left: return .up
        }
    }

    var opposite: Direction {
        leftTurn.leftTurn
    }

    var shortLabel: String {
        switch self {
        case .up: return "N"
        case .down: return "S"
        case .left: return "W"
        case .right: return "E"
        }
    }
}

enum ActionCommand: Equatable {
    case move(Direction)
    case turnLeft
    case turnRight
    case moveBackward
    case interact
    case openInventory
    case dropInventoryItem
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
    case ashenBlade
    case wandererCloak
    case sunCharm
    case barrowMail
    case fenLance
    case mirrorCharm
}

enum ItemKind: String, Codable {
    case consumable
    case key
    case quest
    case upgrade
    case equipment
}

enum EquipmentSlot: String, Codable, CaseIterable {
    case weapon
    case armor
    case charm
}

enum TraitStat: String, Codable, CaseIterable {
    case brawn
    case agility
    case grit
    case wits
    case lore
    case spark

    var shortLabel: String {
        switch self {
        case .brawn: return "BRN"
        case .agility: return "AGI"
        case .grit: return "GRT"
        case .wits: return "WIT"
        case .lore: return "LOR"
        case .spark: return "SPK"
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct TraitProfile: Codable, Equatable {
    var brawn: Int
    var agility: Int
    var grit: Int
    var wits: Int
    var lore: Int
    var spark: Int

    func value(for trait: TraitStat) -> Int {
        switch trait {
        case .brawn: return brawn
        case .agility: return agility
        case .grit: return grit
        case .wits: return wits
        case .lore: return lore
        case .spark: return spark
        }
    }
}

enum SkillID: String, Codable, CaseIterable {
    case bulwark
    case cleave
    case fieldMedicine
    case scavenger
    case trailcraft
    case runeSight

    var displayName: String {
        switch self {
        case .bulwark: return "Bulwark"
        case .cleave: return "Cleave"
        case .fieldMedicine: return "Field Medicine"
        case .scavenger: return "Scavenger"
        case .trailcraft: return "Trailcraft"
        case .runeSight: return "Rune Sight"
        }
    }

    var summary: String {
        switch self {
        case .bulwark: return "+1 defense in every fight."
        case .cleave: return "+1 attack with all weapons."
        case .fieldMedicine: return "Healing tonics restore +4 more."
        case .scavenger: return "Carry two more inventory items."
        case .trailcraft: return "The fen drains lantern charge more slowly."
        case .runeSight: return "Mirror switch mistakes preserve your current progress."
        }
    }
}

enum HeroClass: String, Codable, CaseIterable {
    case warden
    case wayfarer
    case seer

    var displayName: String {
        switch self {
        case .warden: return "Warden"
        case .wayfarer: return "Wayfarer"
        case .seer: return "Seer"
        }
    }

    var summary: String {
        switch self {
        case .warden: return "A hard front-line guardian built to weather attrition."
        case .wayfarer: return "A practical roamer with better sustain and carrying capacity."
        case .seer: return "A ritualist who bends light, runes, and strange machinery."
        }
    }
}

struct HeroTemplate: Codable {
    let heroClass: HeroClass
    let title: String
    let summary: String
    let traits: TraitProfile
    let skills: [SkillID]
    let baseHealth: Int
    let baseStamina: Int
    let baseAttack: Int
    let baseDefense: Int
    let baseLantern: Int
    let startingMarks: Int
    let startingEquipment: EquipmentLoadout
    let startingInventory: [ItemID]
}

struct Item: Codable, Equatable {
    let id: ItemID
    let name: String
    let kind: ItemKind
    let value: Int
    let slot: EquipmentSlot?
    let attackBonus: Int
    let defenseBonus: Int
    let lanternBonus: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case value
        case slot
        case attackBonus
        case defenseBonus
        case lanternBonus
    }

    init(
        id: ItemID,
        name: String,
        kind: ItemKind,
        value: Int,
        slot: EquipmentSlot?,
        attackBonus: Int,
        defenseBonus: Int,
        lanternBonus: Int
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.value = value
        self.slot = slot
        self.attackBonus = attackBonus
        self.defenseBonus = defenseBonus
        self.lanternBonus = lanternBonus
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ItemID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ItemKind.self, forKey: .kind)
        value = try container.decode(Int.self, forKey: .value)
        slot = try container.decodeIfPresent(EquipmentSlot.self, forKey: .slot)
        attackBonus = try container.decodeIfPresent(Int.self, forKey: .attackBonus) ?? 0
        defenseBonus = try container.decodeIfPresent(Int.self, forKey: .defenseBonus) ?? 0
        lanternBonus = try container.decodeIfPresent(Int.self, forKey: .lanternBonus) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(slot, forKey: .slot)
        try container.encode(attackBonus, forKey: .attackBonus)
        try container.encode(defenseBonus, forKey: .defenseBonus)
        try container.encode(lanternBonus, forKey: .lanternBonus)
    }

    var isEquippable: Bool {
        kind == .equipment && slot != nil
    }
}

struct EquipmentLoadout: Codable, Equatable {
    var weapon: ItemID?
    var armor: ItemID?
    var charm: ItemID?

    func itemID(for slot: EquipmentSlot) -> ItemID? {
        switch slot {
        case .weapon: return weapon
        case .armor: return armor
        case .charm: return charm
        }
    }

    mutating func set(_ itemID: ItemID?, for slot: EquipmentSlot) {
        switch slot {
        case .weapon:
            weapon = itemID
        case .armor:
            armor = itemID
        case .charm:
            charm = itemID
        }
    }
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
