import Foundation
import Testing
@testable import Game

@Test func mapParserRejectsRaggedMaps() async throws {
    let loader = ContentLoader()
    let invalid = MapDefinition(
        id: "bad",
        name: "Bad",
        layoutFile: "bad.txt",
        lines: ["###", "##"],
        spawn: Position(x: 1, y: 1),
        portals: [],
        interactables: []
    )
    #expect(throws: ContentError.self) {
        try loader.validate(map: invalid)
    }
}

@Test func collisionBlocksWallsAndWater() async throws {
    let wall = TileFactory.tile(for: "#")
    let water = TileFactory.tile(for: "~")
    let floor = TileFactory.tile(for: ".")

    #expect(wall.walkable == false)
    #expect(water.walkable == false)
    #expect(floor.walkable == true)
}

@Test func combatFormulaStaysInExpectedRange() async throws {
    let values = (0..<6).map { CombatSystem.damage(attackerAttack: 8, defenderDefense: 3, turnIndex: $0) }
    #expect(values.min() == 6)
    #expect(values.max() == 8)
}

@Test func saveRoundTripPersistsState() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let repo = SaveRepository(fileURL: temp)
    let save = SaveGame(
        player: PlayerState(
            name: "Mira",
            heroClass: .wayfarer,
            traits: heroTemplate(for: .wayfarer).traits,
            skills: heroTemplate(for: .wayfarer).skills,
            health: 10,
            maxHealth: 20,
            stamina: 5,
            maxStamina: 10,
            attack: 4,
            defense: 2,
            lanternCharge: 3,
            marks: 10,
            inventory: [],
            equipment: EquipmentLoadout(),
            position: Position(x: 1, y: 1),
            currentMapID: "merrow_village",
            lastSavePosition: Position(x: 1, y: 1),
            lastSaveMapID: "merrow_village"
        ),
        world: WorldState(maps: [:], npcs: [], enemies: [], openedInteractables: [], activeSwitchSequence: []),
        quests: QuestState(flags: [.metElder]),
        playTimeSeconds: 42,
        adventureID: .ashesOfMerrow
    )

    try repo.save(save)
    let loaded = try repo.load()
    #expect(loaded.playTimeSeconds == 42)
    #expect(loaded.quests.has(QuestFlag.metElder))
}

@Test func questObjectiveAdvances() async throws {
    var quests = QuestState()
    #expect(QuestSystem.objective(for: quests) == "Seek Elder Rowan in Merrow.")
    quests.set(.metElder)
    quests.set(.southShrineLit)
    quests.set(.orchardShrineLit)
    #expect(QuestSystem.objective(for: quests) == "Recover the Lens Core in the Barrows.")
}

@Test func inputParserUnderstandsArrowEscape() async throws {
    let parsed = InputParser.parse(bytes: [27, 91, 67])
    #expect(parsed == .move(.right))
}

@Test func inputParserRecognizesDropCommands() async throws {
    #expect(InputParser.parse(character: "r") == .dropInventoryItem)
    #expect(try AutomationCommandParser.parse("drop") == .game(.dropInventoryItem))
}

@Test func screenBufferRendersExpectedLine() async throws {
    var buffer = ScreenBuffer(width: 8, height: 2)
    buffer.write("MERROW", x: 1, y: 0)
    #expect(buffer.line(0) == " MERROW ")
}

@Test func launchModeDefaultsToGraphicsButAllowsTerminalOverride() async throws {
    #expect(LaunchMode.parse(arguments: ["Game"]) == .graphics)
    #expect(LaunchMode.parse(arguments: ["Game", "--terminal"]) == .terminal)
}

@Test func graphicsVisualThemeCyclesBetweenModes() async throws {
    #expect(GraphicsVisualTheme.gemstone.next() == .ultima)
    #expect(GraphicsVisualTheme.ultima.next() == .depth3D)
    #expect(GraphicsVisualTheme.depth3D.next() == .gemstone)
}

@Test func graphicsThemePreferenceRoundTrips() async throws {
    let suiteName = "codexitma.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = GraphicsPreferenceStore(defaults: defaults)
    #expect(store.loadTheme() == .gemstone)
    store.saveTheme(.depth3D)
    #expect(store.loadTheme() == .depth3D)
}

@Test func depthRaycasterMeasuresCenterWallDistance() async throws {
    let map = [
        "#####",
        "#...#",
        "#####"
    ]

    let caster = DepthRaycaster(
        origin: CGPoint(x: 2.5, y: 1.5),
        facing: .right
    ) { position in
        guard position.y >= 0,
              position.y < map.count,
              position.x >= 0,
              position.x < map[position.y].count else {
            return TileFactory.tile(for: "#")
        }
        let raw = Array(map[position.y])[position.x]
        return TileFactory.tile(for: raw)
    }

    let sample = try #require(caster.castSamples(columns: 1, maxDistance: 8).first)
    #expect(sample.didHit)
    #expect(abs(sample.correctedDistance - 1.5) < 0.001)
}

@Test func movementUpdatesPlayerFacing() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)
    engine.handle(.move(.left))

    #expect(engine.state.player.facing == .left)
}

@Test func turningAndBackstepPreserveDungeonCrawlerFacing() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)

    let start = engine.state.player.position
    engine.handle(.turnRight)
    #expect(engine.state.player.facing == .right)
    #expect(engine.state.player.position == start)

    engine.handle(.moveBackward)
    #expect(engine.state.player.facing == .right)
    #expect(engine.state.player.position == Position(x: start.x - 1, y: start.y))
}

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
    #expect(engine.state.mode == .shop)
    #expect(engine.state.shopOffers.count >= 3)

    let marksBefore = engine.state.player.marks
    let inventoryBefore = engine.state.player.inventory.count
    engine.handle(.confirm)

    #expect(engine.state.player.marks == marksBefore - 2)
    #expect(engine.state.player.inventory.count == inventoryBefore + 1)
    #expect(engine.state.world.purchasedShopOffers.isEmpty)
}

@Test func terminalInventoryPanelScrollsPastFiveItems() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)
    engine.state.mode = .inventory
    engine.state.messages = []
    engine.state.player.inventory = [
        itemTable[.healingTonic]!,
        itemTable[.ironKey]!,
        itemTable[.lanternOil]!,
        itemTable[.charmFragment]!,
        itemTable[.shrineKey]!,
        itemTable[.fenLance]!
    ]
    engine.state.inventorySelectionIndex = 5

    let frame = TerminalRenderer().makeFrame(for: engine.state)

    #expect(frame.line(16).contains(itemTable[.ironKey]!.name))
    #expect(!frame.line(16).contains(itemTable[.healingTonic]!.name))
    #expect(frame.line(20).contains(">\(itemTable[.fenLance]!.name)"))
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
        dialogues: [],
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
    let tokens = AutomationTokenizer.tokens(from: "new, right  # comment\nleft\nstate")
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
