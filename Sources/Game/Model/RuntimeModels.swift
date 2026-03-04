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
