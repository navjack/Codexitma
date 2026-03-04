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

@Test func launchOptionsSelectSDLGraphicsBackend() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--sdl"])
    #expect(options.target == .interactive(.graphics))
    #expect(options.graphicsBackend == .sdl)
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
    #expect((depth.depth?.samples.count ?? 0) == 96)
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
