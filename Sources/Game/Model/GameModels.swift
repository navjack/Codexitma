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

struct AdventureID: RawRepresentable, Codable, Hashable, Equatable, ExpressibleByStringLiteral, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    static let ashesOfMerrow = AdventureID(rawValue: "ashesOfMerrow")
    static let starfallRequiem = AdventureID(rawValue: "starfallRequiem")
}

struct AdventureCatalogEntry: Codable, Equatable {
    let id: AdventureID
    let folder: String
    let packFile: String
    let title: String
    let summary: String
    let introLine: String
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
    var heroClass: HeroClass
    var traits: TraitProfile
    var skills: [SkillID]
    var health: Int
    var maxHealth: Int
    var stamina: Int
    var maxStamina: Int
    var attack: Int
    var defense: Int
    var lanternCharge: Int
    var marks: Int
    var inventory: [Item]
    var equipment: EquipmentLoadout = EquipmentLoadout()
    var position: Position
    var currentMapID: String
    var lastSavePosition: Position
    var lastSaveMapID: String

    enum CodingKeys: String, CodingKey {
        case name
        case heroClass
        case traits
        case skills
        case health
        case maxHealth
        case stamina
        case maxStamina
        case attack
        case defense
        case lanternCharge
        case marks
        case inventory
        case equipment
        case position
        case currentMapID
        case lastSavePosition
        case lastSaveMapID
    }

    init(
        name: String,
        heroClass: HeroClass,
        traits: TraitProfile,
        skills: [SkillID],
        health: Int,
        maxHealth: Int,
        stamina: Int,
        maxStamina: Int,
        attack: Int,
        defense: Int,
        lanternCharge: Int,
        marks: Int,
        inventory: [Item],
        equipment: EquipmentLoadout = EquipmentLoadout(),
        position: Position,
        currentMapID: String,
        lastSavePosition: Position,
        lastSaveMapID: String
    ) {
        self.name = name
        self.heroClass = heroClass
        self.traits = traits
        self.skills = skills
        self.health = health
        self.maxHealth = maxHealth
        self.stamina = stamina
        self.maxStamina = maxStamina
        self.attack = attack
        self.defense = defense
        self.lanternCharge = lanternCharge
        self.marks = marks
        self.inventory = inventory
        self.equipment = equipment
        self.position = position
        self.currentMapID = currentMapID
        self.lastSavePosition = lastSavePosition
        self.lastSaveMapID = lastSaveMapID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackTemplate = heroTemplate(for: .wayfarer)

        name = try container.decode(String.self, forKey: .name)
        heroClass = try container.decodeIfPresent(HeroClass.self, forKey: .heroClass) ?? .wayfarer
        traits = try container.decodeIfPresent(TraitProfile.self, forKey: .traits) ?? fallbackTemplate.traits
        skills = try container.decodeIfPresent([SkillID].self, forKey: .skills) ?? fallbackTemplate.skills
        health = try container.decode(Int.self, forKey: .health)
        maxHealth = try container.decode(Int.self, forKey: .maxHealth)
        stamina = try container.decode(Int.self, forKey: .stamina)
        maxStamina = try container.decode(Int.self, forKey: .maxStamina)
        attack = try container.decode(Int.self, forKey: .attack)
        defense = try container.decode(Int.self, forKey: .defense)
        lanternCharge = try container.decode(Int.self, forKey: .lanternCharge)
        marks = try container.decodeIfPresent(Int.self, forKey: .marks) ?? fallbackTemplate.startingMarks
        inventory = try container.decode([Item].self, forKey: .inventory)
        equipment = try container.decodeIfPresent(EquipmentLoadout.self, forKey: .equipment) ?? EquipmentLoadout()
        position = try container.decode(Position.self, forKey: .position)
        currentMapID = try container.decode(String.self, forKey: .currentMapID)
        lastSavePosition = try container.decode(Position.self, forKey: .lastSavePosition)
        lastSaveMapID = try container.decode(String.self, forKey: .lastSaveMapID)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(heroClass, forKey: .heroClass)
        try container.encode(traits, forKey: .traits)
        try container.encode(skills, forKey: .skills)
        try container.encode(health, forKey: .health)
        try container.encode(maxHealth, forKey: .maxHealth)
        try container.encode(stamina, forKey: .stamina)
        try container.encode(maxStamina, forKey: .maxStamina)
        try container.encode(attack, forKey: .attack)
        try container.encode(defense, forKey: .defense)
        try container.encode(lanternCharge, forKey: .lanternCharge)
        try container.encode(marks, forKey: .marks)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(position, forKey: .position)
        try container.encode(currentMapID, forKey: .currentMapID)
        try container.encode(lastSavePosition, forKey: .lastSavePosition)
        try container.encode(lastSaveMapID, forKey: .lastSaveMapID)
    }

    func equipmentItem(for slot: EquipmentSlot) -> Item? {
        guard let itemID = equipment.itemID(for: slot) else { return nil }
        return itemTable[itemID]
    }

    func hasSkill(_ skill: SkillID) -> Bool {
        skills.contains(skill)
    }

    func equippedName(for slot: EquipmentSlot) -> String {
        equipmentItem(for: slot)?.name ?? "None"
    }

    func effectiveAttack() -> Int {
        let equipmentBonus = EquipmentSlot.allCases.reduce(0) { partial, slot in
            partial + (equipmentItem(for: slot)?.attackBonus ?? 0)
        }
        let traitBonus = traits.brawn / 3
        let skillBonus = hasSkill(.cleave) ? 1 : 0
        return attack + equipmentBonus + traitBonus + skillBonus
    }

    func effectiveDefense() -> Int {
        let equipmentBonus = EquipmentSlot.allCases.reduce(0) { partial, slot in
            partial + (equipmentItem(for: slot)?.defenseBonus ?? 0)
        }
        let traitBonus = traits.grit / 3
        let skillBonus = hasSkill(.bulwark) ? 1 : 0
        return defense + equipmentBonus + traitBonus + skillBonus
    }

    func effectiveLanternCapacity() -> Int {
        let equipmentBonus = EquipmentSlot.allCases.reduce(0) { partial, slot in
            partial + (equipmentItem(for: slot)?.lanternBonus ?? 0)
        }
        return lanternCharge + equipmentBonus + (traits.spark / 2)
    }

    func inventoryCapacity() -> Int {
        8 + (hasSkill(.scavenger) ? 2 : 0)
    }

    func tonicHealingAmount(base: Int) -> Int {
        base + (hasSkill(.fieldMedicine) ? 4 : 0)
    }

    func traitSummaryLine() -> String {
        "\(TraitStat.brawn.shortLabel):\(traits.brawn) \(TraitStat.agility.shortLabel):\(traits.agility) \(TraitStat.grit.shortLabel):\(traits.grit)"
    }

    func traitSummaryLineSecondary() -> String {
        "\(TraitStat.wits.shortLabel):\(traits.wits) \(TraitStat.lore.shortLabel):\(traits.lore) \(TraitStat.spark.shortLabel):\(traits.spark)"
    }
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
    case plate
    case switchRune
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

struct QuestStageDefinition: Codable, Equatable {
    let objective: String
    let completeWhenFlag: QuestFlag
}

struct QuestFlowDefinition: Codable, Equatable {
    let stages: [QuestStageDefinition]
    let completionText: String
}

struct ShopOffer: Codable, Equatable {
    let id: String
    let itemID: ItemID
    let price: Int
    let blurb: String
    let repeatable: Bool
}

struct ShopDefinition: Codable {
    let id: String
    let merchantID: NPCID
    let merchantName: String
    let introLine: String
    let offers: [ShopOffer]
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
    var activeSwitchSequence: [String]
    var purchasedShopOffers: Set<String>

    enum CodingKeys: String, CodingKey {
        case maps
        case npcs
        case enemies
        case openedInteractables
        case activeSwitchSequence
        case purchasedShopOffers
    }

    init(
        maps: [String: MapDefinition],
        npcs: [NPCState],
        enemies: [EnemyState],
        openedInteractables: Set<String>,
        activeSwitchSequence: [String] = [],
        purchasedShopOffers: Set<String> = []
    ) {
        self.maps = maps
        self.npcs = npcs
        self.enemies = enemies
        self.openedInteractables = openedInteractables
        self.activeSwitchSequence = activeSwitchSequence
        self.purchasedShopOffers = purchasedShopOffers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maps = try container.decode([String: MapDefinition].self, forKey: .maps)
        npcs = try container.decode([NPCState].self, forKey: .npcs)
        enemies = try container.decode([EnemyState].self, forKey: .enemies)
        openedInteractables = try container.decode(Set<String>.self, forKey: .openedInteractables)
        activeSwitchSequence = try container.decodeIfPresent([String].self, forKey: .activeSwitchSequence) ?? []
        purchasedShopOffers = try container.decodeIfPresent(Set<String>.self, forKey: .purchasedShopOffers) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maps, forKey: .maps)
        try container.encode(npcs, forKey: .npcs)
        try container.encode(enemies, forKey: .enemies)
        try container.encode(openedInteractables, forKey: .openedInteractables)
        try container.encode(activeSwitchSequence, forKey: .activeSwitchSequence)
        try container.encode(purchasedShopOffers, forKey: .purchasedShopOffers)
    }
}

struct SaveGame: Codable {
    var player: PlayerState
    var world: WorldState
    var quests: QuestState
    var playTimeSeconds: Int
    var adventureID: AdventureID

    enum CodingKeys: String, CodingKey {
        case player
        case world
        case quests
        case playTimeSeconds
        case adventureID
    }

    init(
        player: PlayerState,
        world: WorldState,
        quests: QuestState,
        playTimeSeconds: Int,
        adventureID: AdventureID
    ) {
        self.player = player
        self.world = world
        self.quests = quests
        self.playTimeSeconds = playTimeSeconds
        self.adventureID = adventureID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        player = try container.decode(PlayerState.self, forKey: .player)
        world = try container.decode(WorldState.self, forKey: .world)
        quests = try container.decode(QuestState.self, forKey: .quests)
        playTimeSeconds = try container.decode(Int.self, forKey: .playTimeSeconds)
        adventureID = try container.decodeIfPresent(AdventureID.self, forKey: .adventureID) ?? .ashesOfMerrow
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(player, forKey: .player)
        try container.encode(world, forKey: .world)
        try container.encode(quests, forKey: .quests)
        try container.encode(playTimeSeconds, forKey: .playTimeSeconds)
        try container.encode(adventureID, forKey: .adventureID)
    }
}

struct GameContent: @unchecked Sendable {
    let id: AdventureID
    let title: String
    let summary: String
    let introLine: String
    let questFlow: QuestFlowDefinition
    let maps: [String: MapDefinition]
    let dialogues: [String: DialogueNode]
    let encounters: [String: EncounterDefinition]
    let items: [ItemID: Item]
    let shops: [NPCID: ShopDefinition]
    let initialNPCs: [NPCState]
    let initialEnemies: [EnemyState]
}

struct GameContentLibrary: @unchecked Sendable {
    let catalog: [AdventureCatalogEntry]
    let adventures: [AdventureID: GameContent]

    func content(for adventureID: AdventureID) -> GameContent {
        if let content = adventures[adventureID] {
            return content
        }
        if let first = catalog.first, let content = adventures[first.id] {
            return content
        }
        return adventures[.ashesOfMerrow]!
    }

    func entry(for adventureID: AdventureID) -> AdventureCatalogEntry? {
        catalog.first { $0.id == adventureID }
    }

    func contains(_ adventureID: AdventureID) -> Bool {
        adventures[adventureID] != nil
    }
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
    var currentAdventureID: AdventureID
    var availableAdventures: [AdventureCatalogEntry]
    var questFlow: QuestFlowDefinition
    var messages: [String]
    var currentDialogue: DialogueNode?
    var shouldQuit = false
    var playTimeSeconds = 0
    var inventorySelectionIndex = 0
    var activeShopID: NPCID?
    var shopSelectionIndex = 0
    var shopTitle: String?
    var shopLines: [String] = []
    var shopOffers: [ShopOffer] = []
    var shopDetail: String?
    var selectedHeroIndex = 0
    var selectedAdventureIndex = 0

    mutating func log(_ message: String) {
        messages.append(message)
        if messages.count > 8 {
            messages.removeFirst(messages.count - 8)
        }
    }

    mutating func clampInventorySelection() {
        if player.inventory.isEmpty {
            inventorySelectionIndex = 0
        } else {
            inventorySelectionIndex = max(0, min(inventorySelectionIndex, player.inventory.count - 1))
        }
    }

    mutating func clampShopSelection(offerCount: Int) {
        if offerCount <= 0 {
            shopSelectionIndex = 0
        } else {
            shopSelectionIndex = max(0, min(shopSelectionIndex, offerCount - 1))
        }
    }

    mutating func clearShopPanel() {
        activeShopID = nil
        shopSelectionIndex = 0
        shopTitle = nil
        shopLines = []
        shopOffers = []
        shopDetail = nil
    }

    func selectedHeroClass() -> HeroClass {
        let classes = HeroClass.allCases
        guard !classes.isEmpty else { return .wayfarer }
        return classes[(selectedHeroIndex % classes.count + classes.count) % classes.count]
    }

    func selectedAdventureID() -> AdventureID {
        selectedAdventureEntry()?.id ?? .ashesOfMerrow
    }

    func selectedAdventureEntry() -> AdventureCatalogEntry? {
        guard !availableAdventures.isEmpty else { return nil }
        let index = (selectedAdventureIndex % availableAdventures.count + availableAdventures.count) % availableAdventures.count
        return availableAdventures[index]
    }

    func selectedAdventureTitle() -> String {
        selectedAdventureEntry()?.title ?? "Ashes of Merrow"
    }

    func selectedAdventureSummary() -> String {
        selectedAdventureEntry()?.summary ?? "A dying valley, two shrines, and a final beacon against the dark."
    }
}

extension EnemyState: RenderableEntity {}

extension NPCState: RenderableEntity {
    var glyph: Character { glyphSymbol }
    var color: ANSIColor { glyphColor }
}

let adventureCatalogEntries: [AdventureCatalogEntry] = {
    guard let url = Bundle.module.url(forResource: "adventure_catalog", withExtension: "json") else {
        return []
    }

    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([AdventureCatalogEntry].self, from: data)
    } catch {
        preconditionFailure("Failed to decode adventure_catalog.json: \(error)")
    }
}()

let heroTemplateTable: [HeroClass: HeroTemplate] = {
    let descriptor = ("hero_templates" as NSString)
    guard let url = Bundle.module.url(forResource: descriptor.deletingPathExtension, withExtension: "json") else {
        preconditionFailure("Missing hero_templates.json in bundled resources.")
    }

    do {
        let data = try Data(contentsOf: url)
        let templates = try JSONDecoder().decode([HeroTemplate].self, from: data)
        return Dictionary(uniqueKeysWithValues: templates.map { ($0.heroClass, $0) })
    } catch {
        preconditionFailure("Failed to decode hero_templates.json: \(error)")
    }
}()

func heroTemplate(for heroClass: HeroClass) -> HeroTemplate {
    heroTemplateTable[heroClass] ?? heroTemplateTable[.wayfarer]!
}
