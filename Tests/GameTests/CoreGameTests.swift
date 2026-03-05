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

@Test func automationParsersRecognizeDropCommands() async throws {
    #expect(try AutomationCommandParser.parse("drop") == .game(.dropInventoryItem))
}

@Test func automationParsersRecognizeCoordinateWarpCommands() async throws {
    #expect(
        try AutomationCommandParser.parse("warp:10:12")
            == .warp(mapID: nil, position: Position(x: 10, y: 12), facing: nil)
    )
    #expect(
        try AutomationCommandParser.parse("warp:10:12:n")
            == .warp(mapID: nil, position: Position(x: 10, y: 12), facing: .up)
    )
    #expect(
        try AutomationCommandParser.parse("warp:merrow_village:9:6")
            == .warp(mapID: "merrow_village", position: Position(x: 9, y: 6), facing: nil)
    )
    #expect(
        try AutomationCommandParser.parse("tp:merrow_village:9:6:w")
            == .warp(mapID: "merrow_village", position: Position(x: 9, y: 6), facing: .left)
    )
}

@Test func graphicsAutomationParsersRecognizeScreenshotAndThemeCommands() async throws {
    #expect(try GraphicsAutomationCommandParser.parse("shot") == .screenshot(nil))
    #expect(try GraphicsAutomationCommandParser.parse("shot:title-ashesofmerrow") == .screenshot("title-ashesofmerrow"))
    #expect(try GraphicsAutomationCommandParser.parse("style") == .cycleTheme)
    #expect(try GraphicsAutomationCommandParser.parse("theme:depth3d") == .selectTheme(.depth3D))
    #expect(try GraphicsAutomationCommandParser.parse("theme:gemstone") == .selectTheme(.gemstone))
    #expect(try GraphicsAutomationCommandParser.parse("e") == .game(.interact))
}

@Test func launchOptionsRemainGraphicsOnlyEvenWithLegacyTerminalFlag() async throws {
    let defaultOptions = try LaunchOptions.parse(arguments: ["Game"])
    #expect(defaultOptions.target == .interactive)

    let legacyOptions = try LaunchOptions.parse(arguments: ["Game", "--terminal"])
    #expect(legacyOptions.target == .interactive)
    #expect(legacyOptions.graphicsBackend == .native)
}

@Test func launchOptionsSelectSDLGraphicsBackend() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--sdl"])
    #expect(options.target == .interactive)
    #expect(options.graphicsBackend == .sdl)
}

@Test func launchOptionsDoNotLetGraphicsFlagsOverrideNonInteractiveModes() async throws {
    let scriptOptions = try LaunchOptions.parse(arguments: ["Game", "--script", "state", "--sdl"])
    #expect(scriptOptions.target == .script)
    #expect(scriptOptions.graphicsBackend == .sdl)
    #expect(scriptOptions.commands == ["state"])

    let graphicsScriptOptions = try LaunchOptions.parse(arguments: ["Game", "--graphics-script", "theme:gemstone,shot", "--sdl"])
    #expect(graphicsScriptOptions.target == .graphicsScript)
    #expect(graphicsScriptOptions.graphicsBackend == .sdl)
    #expect(graphicsScriptOptions.commands == ["theme:gemstone", "shot"])

    let bridgeOptions = try LaunchOptions.parse(arguments: ["Game", "--bridge", "--sdl"])
    #expect(bridgeOptions.target == .bridge)
    #expect(bridgeOptions.graphicsBackend == .sdl)

    let editorOptions = try LaunchOptions.parse(arguments: ["Game", "--editor", "--sdl"])
    #expect(editorOptions.target == .editor)
    #expect(editorOptions.graphicsBackend == .sdl)
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

@Test func graphicsSceneSnapshotBuildsBoardAndDepthViewData() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    let topDown = GraphicsSceneSnapshotBuilder.build(state: engine.state, visualTheme: .gemstone)
    #expect(topDown.board.width > 0)
    #expect(topDown.board.height > 0)
    #expect(topDown.depth == nil)
    #expect(topDown.availableAdventures.isEmpty == false)
    #expect(topDown.selectedHeroClass == engine.state.selectedHeroClass())

    let depth = GraphicsSceneSnapshotBuilder.build(state: engine.state, visualTheme: .depth3D)
    #expect(depth.depth != nil)
    #expect((depth.depth?.samples.count ?? 0) >= 96)
    #expect((depth.depth?.maxDistance ?? 0) >= 8.5)
    #expect((depth.depth?.samples.first?.lightLevel ?? 0) > 0)
}

@Test func sharedGameSessionUsesSameDepthControlRemapAsNativeGraphics() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")

    let session = await MainActor.run {
        SharedGameSession(
            library: library,
            saveRepository: SaveRepository(fileURL: saveURL),
            soundEngine: SilentGameSoundEngine.shared
        )
    }

    await MainActor.run {
        session.send(.newGame)
        session.send(.confirm)
        let start = session.state.player.position
        let startFacing = session.state.player.facing

        session.selectVisualTheme(.depth3D)
        session.send(.move(.left))

        #expect(session.state.player.facing == startFacing.leftTurn)
        #expect(session.state.player.position == start)
    }
}

@Test func sharedGameSessionUsesSelectedOrCurrentAdventureForEditorTarget() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")

    let session = await MainActor.run {
        SharedGameSession(
            library: library,
            saveRepository: SaveRepository(fileURL: saveURL),
            soundEngine: SilentGameSoundEngine.shared
        )
    }

    await MainActor.run {
        session.send(.move(.right))
        #expect(session.editorTargetAdventureID() == session.state.selectedAdventureID())
        #expect(session.canOpenEditorFromCurrentMode())

        session.send(.newGame)
        session.send(.confirm)

        #expect(session.editorTargetAdventureID() == session.state.currentAdventureID)
        #expect(session.editorConfirmationLines().isEmpty == false)
    }
}

@Test func depthRaycasterMeasuresCenterWallDistance() async throws {
    let map = [
        "#####",
        "#...#",
        "#####"
    ]

    let caster = DepthRaycaster(
        origin: DepthPoint(x: 2.5, y: 1.5),
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
