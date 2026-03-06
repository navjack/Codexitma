import Foundation
import Testing
@testable import Game

@Test func contentLoaderLoadsAdventureLibrary() async throws {
    let library = try ContentLoader().load()
    #expect(library.adventures.count == 2)
    let merrow = library.content(for: .ashesOfMerrow)
    let starfall = library.content(for: .starfallRequiem)
    #expect(merrow.maps.count == 6)
    #expect(starfall.maps.count == 10)
    #expect(merrow.initialNPCs.count >= 5)
    #expect(starfall.initialNPCs.count >= 9)
    #expect(starfall.initialEnemies.count >= 16)
    #expect(merrow.shops.isEmpty)
    #expect(starfall.shops.count >= 3)
    #expect(adventureCatalogEntries.count == 2)
    #expect(itemTable.count >= 12)
}

@Test func shopsSpendMarksAndRecordStock() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.move(.right))
    engine.handle(.newGame)
    engine.handle(.confirm)

    for _ in 0..<7 {
        engine.handle(.move(.right))
    }
    for _ in 0..<4 {
        engine.handle(.move(.up))
    }

    #expect(engine.state.player.currentMapID == "signal_bazaar")

    for _ in 0..<3 {
        engine.handle(.move(.up))
    }

    engine.handle(.interact)
    #expect(engine.state.mode == .dialogue)

    engine.handle(.confirm)
    #expect(engine.state.mode == .shop)
    #expect(engine.state.shopOffers.count >= 3)

    let marksBefore = engine.state.player.marks
    let inventoryBefore = engine.state.player.inventory.count
    engine.handle(.confirm)

    #expect(engine.state.player.marks == marksBefore - 2)
    #expect(engine.state.player.inventory.count == inventoryBefore + 1)
    #expect(engine.state.world.purchasedShopOffers.isEmpty)
}

@Test func contentLoaderQuarantinesBrokenExternalPackInsteadOfBrickingStartup() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let goodPack = root.appendingPathComponent("good_pack", isDirectory: true)
    let badPack = root.appendingPathComponent("bad_pack", isDirectory: true)
    try FileManager.default.createDirectory(at: goodPack, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: badPack, withIntermediateDirectories: true)

    try """
    {
      "id": "goodPack",
      "title": "Good Pack",
      "summary": "Loads cleanly.",
      "introLine": "A clean road opens.",
      "worldFile": "world.json",
      "dialoguesFile": "dialogues.json",
      "objectivesFile": "quest_flow.json",
      "encountersFile": "encounters.json",
      "npcsFile": "npcs.json",
      "enemiesFile": "enemies.json",
      "shopsFile": "shops.json"
    }
    """.write(to: goodPack.appendingPathComponent("adventure.json"), atomically: true, encoding: .utf8)

    try """
    [
      {
        "id": "dock_start",
        "name": "Dock Start",
        "layoutFile": "dock_map.txt",
        "lines": [],
        "spawn": { "x": 1, "y": 1 },
        "portals": [],
        "interactables": []
      }
    ]
    """.write(to: goodPack.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)
    try "###\n#.#\n###\n".write(to: goodPack.appendingPathComponent("dock_map.txt"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: goodPack.appendingPathComponent("dialogues.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: goodPack.appendingPathComponent("encounters.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: goodPack.appendingPathComponent("npcs.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: goodPack.appendingPathComponent("enemies.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: goodPack.appendingPathComponent("shops.json"), atomically: true, encoding: .utf8)
    try """
    {
      "stages": [
        { "objective": "Reach the dock.", "completeWhenFlag": "metElder" }
      ],
      "completionText": "Done."
    }
    """.write(to: goodPack.appendingPathComponent("quest_flow.json"), atomically: true, encoding: .utf8)

    try """
    {
      "id": "badPack",
      "title": "Bad Pack",
      "summary": "Should be skipped.",
      "introLine": "This should not load.",
      "worldFile": "../outside/world.json",
      "dialoguesFile": "dialogues.json",
      "objectivesFile": "quest_flow.json",
      "encountersFile": "encounters.json",
      "npcsFile": "npcs.json",
      "enemiesFile": "enemies.json",
      "shopsFile": "shops.json"
    }
    """.write(to: badPack.appendingPathComponent("adventure.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: badPack.appendingPathComponent("dialogues.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: badPack.appendingPathComponent("encounters.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: badPack.appendingPathComponent("npcs.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: badPack.appendingPathComponent("enemies.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: badPack.appendingPathComponent("shops.json"), atomically: true, encoding: .utf8)
    try """
    {
      "stages": [
        { "objective": "Should never load.", "completeWhenFlag": "metElder" }
      ],
      "completionText": "Done."
    }
    """.write(to: badPack.appendingPathComponent("quest_flow.json"), atomically: true, encoding: .utf8)

    let library = try ContentLoader(externalRootURL: root).load()
    #expect(library.contains(AdventureID(rawValue: "goodPack")))
    #expect(!library.contains(AdventureID(rawValue: "badPack")))
    #expect(library.loadWarnings.isEmpty == false)
}

@Test func contentLoaderUsesFirstMapAsFallbackStartMapForCustomPack() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let packFolder = root.appendingPathComponent("stormkeep_trial", isDirectory: true)
    try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    try """
    {
      "id": "stormkeepTrial",
      "title": "Stormkeep Trial",
      "summary": "A compact external pack for loader validation.",
      "introLine": "A hidden tower hums beyond the surf.",
      "objectivesFile": "quest_flow.json",
      "worldFile": "world.json",
      "dialoguesFile": "dialogues.json",
      "encountersFile": "encounters.json",
      "npcsFile": "npcs.json",
      "enemiesFile": "enemies.json",
      "shopsFile": "shops.json"
    }
    """.write(to: packFolder.appendingPathComponent("adventure.json"), atomically: true, encoding: .utf8)

    try """
    {
      "stages": [
        { "objective": "Reach the tower gate.", "completeWhenFlag": "metElder" }
      ],
      "completionText": "The trial is complete."
    }
    """.write(to: packFolder.appendingPathComponent("quest_flow.json"), atomically: true, encoding: .utf8)

    try """
    [
      {
        "id": "stormkeep_gate",
        "name": "Stormkeep Gate",
        "layoutFile": "stormkeep_map.txt",
        "lines": [],
        "spawn": { "x": 1, "y": 1 },
        "portals": [],
        "interactables": []
      }
    ]
    """.write(to: packFolder.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)

    try "###\n#.#\n###\n".write(to: packFolder.appendingPathComponent("stormkeep_map.txt"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("dialogues.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("encounters.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("npcs.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("enemies.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("shops.json"), atomically: true, encoding: .utf8)

    let library = try ContentLoader(externalRootURL: root).load()
    let externalID = AdventureID(rawValue: "stormkeepTrial")
    let content = library.content(for: externalID)

    #expect(content.startMapID == "stormkeep_gate")
}

@Test func droppingInventoryItemsRemovesConsumablesAndProtectsQuestItems() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)

    engine.state.player.inventory = [
        itemTable[.healingTonic]!,
        itemTable[.lanternOil]!
    ]
    engine.state.mode = .inventory
    engine.state.inventorySelectionIndex = 1
    engine.handle(.dropInventoryItem)

    #expect(engine.state.player.inventory.map(\.id) == [.healingTonic])
    #expect(engine.state.inventorySelectionIndex == 0)
    #expect(engine.state.mode == .inventory)

    engine.state.player.inventory = [itemTable[.lensCore]!]
    engine.state.mode = .inventory
    engine.state.inventorySelectionIndex = 0
    engine.handle(.dropInventoryItem)

    #expect(engine.state.player.inventory.map(\.id) == [.lensCore])
    #expect(engine.state.messages.last == "\(itemTable[.lensCore]!.name) is too important to abandon.")

    engine.state.player.inventory = [itemTable[.healingTonic]!]
    engine.state.mode = .inventory
    engine.state.inventorySelectionIndex = 0
    engine.handle(.dropInventoryItem)

    #expect(engine.state.player.inventory.isEmpty)
    #expect(engine.state.mode == .exploration)
}

@Test func contentLoaderLoadsExternalAdventurePackFromFilesystem() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let packFolder = root.appendingPathComponent("stormkeep_trial", isDirectory: true)
    try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)

    try """
    {
      "id": "stormkeepTrial",
      "title": "Stormkeep Trial",
      "summary": "A compact external pack for loader validation.",
      "introLine": "A hidden tower hums beyond the surf.",
      "objectivesFile": "quest_flow.json",
      "worldFile": "world.json",
      "dialoguesFile": "dialogues.json",
      "encountersFile": "encounters.json",
      "npcsFile": "npcs.json",
      "enemiesFile": "enemies.json",
      "shopsFile": "shops.json"
    }
    """.write(to: packFolder.appendingPathComponent("adventure.json"), atomically: true, encoding: .utf8)

    try """
    {
      "stages": [
        { "objective": "Reach the tower gate.", "completeWhenFlag": "metElder" }
      ],
      "completionText": "The trial is complete."
    }
    """.write(to: packFolder.appendingPathComponent("quest_flow.json"), atomically: true, encoding: .utf8)

    try """
    [
      {
        "id": "merrow_village",
        "name": "Stormkeep Gate",
        "layoutFile": "stormkeep_map.txt",
        "lines": [],
        "spawn": { "x": 1, "y": 1 },
        "portals": [],
        "interactables": []
      }
    ]
    """.write(to: packFolder.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)

    try "###\n#.#\n###\n".write(to: packFolder.appendingPathComponent("stormkeep_map.txt"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("dialogues.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("encounters.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("npcs.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("enemies.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("shops.json"), atomically: true, encoding: .utf8)

    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let library = try ContentLoader(externalRootURL: root).load()
    let externalID = AdventureID(rawValue: "stormkeepTrial")

    #expect(library.catalog.count == 3)
    #expect(library.contains(externalID))
    #expect(library.content(for: externalID).title == "Stormkeep Trial")
}

@Test func contentLoaderAllowsExternalOverrideOfBundledAdventure() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    let packFolder = root.appendingPathComponent("ashes_override", isDirectory: true)
    try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)

    try """
    {
      "id": "ashesOfMerrow",
      "title": "Ashes Override",
      "summary": "An override pack for the bundled adventure.",
      "introLine": "The override rises from the disk.",
      "objectivesFile": "quest_flow.json",
      "worldFile": "world.json",
      "dialoguesFile": "dialogues.json",
      "encountersFile": "encounters.json",
      "npcsFile": "npcs.json",
      "enemiesFile": "enemies.json",
      "shopsFile": "shops.json"
    }
    """.write(to: packFolder.appendingPathComponent("adventure.json"), atomically: true, encoding: .utf8)

    try """
    {
      "stages": [
        { "objective": "Reach the override marker.", "completeWhenFlag": "metElder" }
      ],
      "completionText": "Override complete."
    }
    """.write(to: packFolder.appendingPathComponent("quest_flow.json"), atomically: true, encoding: .utf8)

    try """
    [
      {
        "id": "merrow_village",
        "name": "Override Village",
        "layoutFile": "override_map.txt",
        "lines": [],
        "spawn": { "x": 1, "y": 1 },
        "portals": [],
        "interactables": []
      }
    ]
    """.write(to: packFolder.appendingPathComponent("world.json"), atomically: true, encoding: .utf8)

    try "###\n#.#\n###\n".write(to: packFolder.appendingPathComponent("override_map.txt"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("dialogues.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("encounters.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("npcs.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("enemies.json"), atomically: true, encoding: .utf8)
    try "[]\n".write(to: packFolder.appendingPathComponent("shops.json"), atomically: true, encoding: .utf8)

    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let library = try ContentLoader(externalRootURL: root).load()
    #expect(library.content(for: .ashesOfMerrow).title == "Ashes Override")
    #expect(library.entry(for: .ashesOfMerrow)?.title == "Ashes Override")
}

@Test func adventurePackExporterWritesLoadableExternalPack() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let exporter = AdventurePackExporter(externalRootURL: root)
    let document = EditableAdventureDocument(
        folderName: "forge_test",
        adventureID: "forgeTest",
        title: "Forge Test",
        summary: "A test adventure exported by the editor.",
        introLine: "The forge hums.",
        maps: [
            EditableMap(
                id: "merrow_village",
                name: "Forge Room",
                lines: [
                    "#####",
                    "#...#",
                    "#####"
                ],
                spawn: Position(x: 1, y: 1),
                portals: [],
                interactables: []
            )
        ],
        selectedMapIndex: 0,
        questFlow: QuestFlowDefinition(
            stages: [
                QuestStageDefinition(objective: "Test the export.", completeWhenFlag: .metElder)
            ],
            completionText: "Done."
        ),
        dialogues: [
            DialogueNode(
                id: "forge_intro",
                speaker: "Forge Guide",
                lines: ["The forge is awake."]
            )
        ],
        encounters: [],
        npcs: [],
        enemies: [],
        shops: []
    )

    let packURL = try exporter.save(document: document)
    #expect(FileManager.default.fileExists(atPath: packURL.appendingPathComponent("adventure.json").path))

    let library = try ContentLoader(externalRootURL: root).load()
    let adventureID = AdventureID(rawValue: "forgeTest")
    #expect(library.contains(adventureID))
    #expect(library.content(for: adventureID).maps["merrow_village"]?.name == "Forge Room")
}

@Test func equippedItemsAffectDerivedStats() async throws {
    let player = PlayerState(
        name: "Mira",
        heroClass: .wayfarer,
        traits: TraitProfile(brawn: 5, agility: 5, grit: 5, wits: 5, lore: 5, spark: 4),
        skills: [],
        health: 24,
        maxHealth: 24,
        stamina: 12,
        maxStamina: 12,
        attack: 6,
        defense: 3,
        lanternCharge: 8,
        marks: 10,
        inventory: [],
        equipment: EquipmentLoadout(weapon: .fenLance, armor: .barrowMail, charm: .mirrorCharm),
        position: Position(x: 0, y: 0),
        currentMapID: "merrow_village",
        lastSavePosition: Position(x: 0, y: 0),
        lastSaveMapID: "merrow_village"
    )

    #expect(player.effectiveAttack() == 11)
    #expect(player.effectiveDefense() == 7)
    #expect(player.effectiveLanternCapacity() == 12)
}

@Test func heroTemplateProvidesDistinctClasses() async throws {
    let warden = heroTemplate(for: .warden)
    let seer = heroTemplate(for: .seer)
    #expect(warden.heroClass == .warden)
    #expect(seer.traits.spark > warden.traits.spark)
    #expect(warden.skills.contains(.bulwark))
}

@Test func automationTokenizerSplitsScriptsAndComments() async throws {
    let tokens = AutomationTokenizer.tokens(from: "# header comment\nnew, right  # comment\nleft\nstate")
    #expect(tokens == ["new", "right", "left", "state"])
}

@Test func automationCommandParserRecognizesMovementAndState() async throws {
    #expect(try AutomationCommandParser.parse("a") == .game(.move(.left)))
    #expect(try AutomationCommandParser.parse("state") == .snapshot)
    #expect(try AutomationCommandParser.parse("turnleft") == .game(.turnLeft))
    #expect(try AutomationCommandParser.parse("backstep") == .game(.moveBackward))
}

@Test func launchOptionsParseScriptMode() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--script", "new,right,e", "--step-json"])
    #expect(options.target == .script)
    #expect(options.commands == ["new", "right", "e"])
    #expect(options.emitStepSnapshots == true)
}

@Test func launchOptionsParseEditorMode() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--editor"])
    #expect(options.target == .editor)
}

@Test func launchOptionsParsePlaytestAdventure() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--graphics", "--playtest", "starfallRequiem"])
    #expect(options.target == .interactive)
    #expect(options.playtestAdventureID == .starfallRequiem)
}
