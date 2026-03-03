import Foundation

enum ContentError: Error {
    case missingResource(String)
    case invalidMap(String)
}

struct ContentLoader {
    func load() throws -> GameContent {
        let bundle = Bundle.module
        guard let worldURL = bundle.url(forResource: "world", withExtension: "json") else {
            throw ContentError.missingResource("world.json")
        }

        let worldData = try Data(contentsOf: worldURL)
        let maps = try JSONDecoder().decode([MapDefinition].self, from: worldData)

        var resolvedMaps: [String: MapDefinition] = [:]
        for map in maps {
            let parts = map.layoutFile.split(separator: ".", maxSplits: 1).map(String.init)
            let resourceName = parts.first ?? map.layoutFile
            let resourceExtension = parts.count > 1 ? parts[1] : nil
            guard let layoutURL = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
                throw ContentError.missingResource(map.layoutFile)
            }
            let raw = try String(contentsOf: layoutURL)
            let lines = raw
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            let resolved = MapDefinition(
                id: map.id,
                name: map.name,
                layoutFile: map.layoutFile,
                lines: lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
            try validate(map: resolved)
            resolvedMaps[resolved.id] = resolved
        }

        return GameContent(
            maps: resolvedMaps,
            dialogues: dialogueTable,
            encounters: encounterTable,
            items: itemTable,
            initialNPCs: npcSeed,
            initialEnemies: enemySeed
        )
    }

    func validate(map: MapDefinition) throws {
        guard let first = map.lines.first else { throw ContentError.invalidMap(map.id) }
        let width = first.count
        for line in map.lines {
            guard line.count == width else { throw ContentError.invalidMap(map.id) }
            for char in line {
                guard TileFactory.isAllowedGlyph(char) else { throw ContentError.invalidMap(map.id) }
            }
        }
    }
}

let itemTable: [ItemID: Item] = [
    .healingTonic: Item(id: .healingTonic, name: "Healing Tonic", kind: .consumable, value: 8, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .ironKey: Item(id: .ironKey, name: "Iron Key", kind: .key, value: 0, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .lanternOil: Item(id: .lanternOil, name: "Lantern Oil", kind: .consumable, value: 6, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .charmFragment: Item(id: .charmFragment, name: "Charm Fragment", kind: .upgrade, value: 1, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .lensCore: Item(id: .lensCore, name: "Lens Core", kind: .quest, value: 0, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .shrineKey: Item(id: .shrineKey, name: "Shrine Key", kind: .key, value: 0, slot: nil, attackBonus: 0, defenseBonus: 0, lanternBonus: 0),
    .ashenBlade: Item(id: .ashenBlade, name: "Ashen Blade", kind: .equipment, value: 0, slot: .weapon, attackBonus: 1, defenseBonus: 0, lanternBonus: 0),
    .wandererCloak: Item(id: .wandererCloak, name: "Wanderer Cloak", kind: .equipment, value: 0, slot: .armor, attackBonus: 0, defenseBonus: 1, lanternBonus: 0),
    .sunCharm: Item(id: .sunCharm, name: "Sun Charm", kind: .equipment, value: 0, slot: .charm, attackBonus: 0, defenseBonus: 0, lanternBonus: 3),
    .barrowMail: Item(id: .barrowMail, name: "Barrow Mail", kind: .equipment, value: 0, slot: .armor, attackBonus: 0, defenseBonus: 2, lanternBonus: 0),
    .fenLance: Item(id: .fenLance, name: "Fen Lance", kind: .equipment, value: 0, slot: .weapon, attackBonus: 3, defenseBonus: 0, lanternBonus: 0),
    .mirrorCharm: Item(id: .mirrorCharm, name: "Mirror Charm", kind: .equipment, value: 0, slot: .charm, attackBonus: 1, defenseBonus: 1, lanternBonus: 2),
]

let dialogueTable: [String: DialogueNode] = [
    "elder_intro": DialogueNode(
        id: "elder_intro",
        speaker: "Elder Rowan",
        lines: [
            "The beacon fell dark at dawn.",
            "Relight the outer shrines and the valley may yet hold.",
        ]
    ),
    "orchard_hermit": DialogueNode(
        id: "orchard_hermit",
        speaker: "Mara the Tinker",
        lines: [
            "Roots remember the old roads.",
            "Carry light, and the orchard will open what it swallowed.",
        ]
    ),
    "fen_ferryman": DialogueNode(
        id: "fen_ferryman",
        speaker: "Fen Ferryman",
        lines: [
            "The mist listens for weak lamps.",
            "Keep the lantern breathing and the bog will spare your feet.",
        ]
    ),
    "field_scout": DialogueNode(
        id: "field_scout",
        speaker: "Watcher Elow",
        lines: [
            "The crows have learned the roads better than we have.",
            "Take the old tonic cache. You'll need it.",
        ]
    ),
    "barrow_scholar": DialogueNode(
        id: "barrow_scholar",
        speaker: "Dust Scholar",
        lines: [
            "The dead built these vaults to test memory.",
            "Take only what light can carry. The rest belongs to stone.",
        ]
    ),
    "keeper": DialogueNode(
        id: "keeper",
        speaker: "The Shaded Keeper",
        lines: [
            "You carry the old light.",
            "Then come. Let shadow test your will.",
        ]
    ),
]

let encounterTable: [String: EncounterDefinition] = [
    "crow": EncounterDefinition(id: "crow", enemyID: "crow_1", introLine: "A ragged crow dives from the rafters."),
    "hound": EncounterDefinition(id: "hound", enemyID: "hound_1", introLine: "A root hound snaps from the thicket."),
]

let npcSeed: [NPCState] = [
    NPCState(
        id: "elder",
        name: "Elder Rowan",
        position: Position(x: 6, y: 5),
        mapID: "merrow_village",
        dialogueID: "elder_intro",
        glyphSymbol: "&",
        glyphColor: .cyan,
        dialogueState: 0
    ),
    NPCState(
        id: "field_scout",
        name: "Watcher Elow",
        position: Position(x: 4, y: 7),
        mapID: "south_fields",
        dialogueID: "field_scout",
        glyphSymbol: "s",
        glyphColor: .white,
        dialogueState: 0
    ),
    NPCState(
        id: "orchard_guide",
        name: "Mara the Tinker",
        position: Position(x: 4, y: 2),
        mapID: "sunken_orchard",
        dialogueID: "orchard_hermit",
        glyphSymbol: "t",
        glyphColor: .green,
        dialogueState: 0
    ),
    NPCState(
        id: "barrow_scholar",
        name: "Dust Scholar",
        position: Position(x: 15, y: 7),
        mapID: "hollow_barrows",
        dialogueID: "barrow_scholar",
        glyphSymbol: "d",
        glyphColor: .magenta,
        dialogueState: 0
    ),
    NPCState(
        id: "fen_ferryman",
        name: "Fen Ferryman",
        position: Position(x: 5, y: 7),
        mapID: "black_fen",
        dialogueID: "fen_ferryman",
        glyphSymbol: "f",
        glyphColor: .yellow,
        dialogueState: 0
    ),
]

let enemySeed: [EnemyState] = [
    EnemyState(id: "crow_1", name: "Crow", position: Position(x: 10, y: 4), hp: 7, maxHP: 7, attack: 4, defense: 1, ai: .idle, glyph: "c", color: .yellow, mapID: "south_fields", active: true),
    EnemyState(id: "crow_2", name: "Crow", position: Position(x: 14, y: 2), hp: 7, maxHP: 7, attack: 4, defense: 1, ai: .idle, glyph: "c", color: .yellow, mapID: "south_fields", active: true),
    EnemyState(id: "hound_1", name: "Root Hound", position: Position(x: 9, y: 6), hp: 10, maxHP: 10, attack: 5, defense: 2, ai: .stalk, glyph: "h", color: .red, mapID: "sunken_orchard", active: true),
    EnemyState(id: "hound_2", name: "Root Hound", position: Position(x: 14, y: 7), hp: 10, maxHP: 10, attack: 5, defense: 2, ai: .stalk, glyph: "h", color: .red, mapID: "sunken_orchard", active: true),
    EnemyState(id: "wraith_1", name: "Mire Wraith", position: Position(x: 8, y: 5), hp: 12, maxHP: 12, attack: 6, defense: 2, ai: .stalk, glyph: "w", color: .magenta, mapID: "black_fen", active: true),
    EnemyState(id: "wraith_2", name: "Mire Wraith", position: Position(x: 12, y: 2), hp: 12, maxHP: 12, attack: 6, defense: 2, ai: .stalk, glyph: "w", color: .magenta, mapID: "black_fen", active: true),
    EnemyState(id: "sentinel_1", name: "Barrow Sentinel", position: Position(x: 12, y: 4), hp: 15, maxHP: 15, attack: 7, defense: 3, ai: .guardian, glyph: "g", color: .white, mapID: "hollow_barrows", active: true),
    EnemyState(id: "sentinel_2", name: "Barrow Sentinel", position: Position(x: 6, y: 7), hp: 15, maxHP: 15, attack: 7, defense: 3, ai: .guardian, glyph: "g", color: .white, mapID: "hollow_barrows", active: true),
    EnemyState(id: "keeper", name: "Shaded Keeper", position: Position(x: 12, y: 4), hp: 18, maxHP: 18, attack: 8, defense: 3, ai: .boss, glyph: "K", color: .brightBlack, mapID: "beacon_spire", active: true),
]
