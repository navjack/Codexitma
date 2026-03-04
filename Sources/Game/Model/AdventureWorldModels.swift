import Foundation

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
    var facing: Direction = .up
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
        case facing
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
        facing: Direction = .up,
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
        self.facing = facing
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
        facing = try container.decodeIfPresent(Direction.self, forKey: .facing) ?? .up
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
        try container.encode(facing, forKey: .facing)
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
    case torchFloor
    case torchWall
}

struct InteractableDefinition: Codable {
    let id: String
    let kind: InteractableKind
    let position: Position
    let title: String
    let lines: [String]
    let rewardItem: ItemID?
    let rewardMarks: Int?
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
