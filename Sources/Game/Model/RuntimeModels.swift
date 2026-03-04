import Foundation

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

let adventureCatalogEntries: [AdventureCatalogEntry] = {
    guard let url = GameResourceBundle.current.url(forResource: "adventure_catalog", withExtension: "json") else {
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
    guard let url = GameResourceBundle.current.url(forResource: descriptor.deletingPathExtension, withExtension: "json") else {
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
