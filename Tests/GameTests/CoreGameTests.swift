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
    #expect(
        try GraphicsAutomationCommandParser.parse("warp:south_fields:5:2:e")
            == .warp(mapID: "south_fields", position: Position(x: 5, y: 2), facing: .right)
    )
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
    #expect(topDown.titleOptions.count == TitleMenuOption.allCases.count)
    #expect(topDown.titleOptions.first?.isSelected == true)
    #expect(topDown.selectedHeroClass == engine.state.selectedHeroClass())

    let depth = GraphicsSceneSnapshotBuilder.build(state: engine.state, visualTheme: .depth3D)
    #expect(depth.depth != nil)
    #expect((depth.depth?.samples.count ?? 0) >= 96)
    #expect((depth.depth?.maxDistance ?? 0) >= 8.5)
    #expect((depth.depth?.samples.first?.lightLevel ?? 0) > 0)
}

@Test func titleMenuUsesVerticalSelectionAndConfirmStartsCharacterCreation() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    #expect(engine.state.mode == .title)
    #expect(engine.state.selectedTitleOption() == .startNewGame)

    engine.handle(.move(.down))

    #expect(engine.state.mode == .title)
    #expect(engine.state.selectedTitleOption() == .loadSave)

    engine.handle(.move(.up))
    engine.handle(.confirm)

    #expect(engine.state.mode == .characterCreation)
    #expect(engine.state.selectedHeroClass() == .warden)
}

@Test func titleMenuKeepsAdventureSelectionOnHorizontalMovement() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))
    let initialTitleOption = engine.state.selectedTitleOption()
    let initialAdventure = engine.state.selectedAdventureID()

    engine.handle(.move(.right))

    #expect(engine.state.selectedTitleOption() == initialTitleOption)
    #expect(engine.state.selectedAdventureID() != initialAdventure || engine.state.availableAdventures.count <= 1)
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

@Test func pauseModeConsumesMovementInsteadOfMovingThePlayer() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)

    let startPosition = engine.state.player.position
    engine.handle(.cancel)

    #expect(engine.state.mode == .pause)
    #expect(engine.state.pauseSelectionIndex == 0)

    engine.handle(.move(.down))

    #expect(engine.state.mode == .pause)
    #expect(engine.state.player.position == startPosition)
    #expect(engine.state.pauseSelectionIndex == 1)

    engine.handle(.cancel)

    #expect(engine.state.mode == .exploration)
    #expect(engine.state.player.position == startPosition)
}

@Test func pauseMenuCanSaveAndReturnToTitle() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let repository = SaveRepository(fileURL: saveURL)
    let engine = GameEngine(library: library, saveRepository: repository)

    engine.handle(.newGame)
    engine.handle(.confirm)
    let currentAdventureID = engine.state.currentAdventureID
    let currentPosition = engine.state.player.position

    engine.handle(.cancel)
    engine.handle(.move(.down))
    engine.handle(.confirm)

    #expect(engine.state.mode == .title)
    #expect(engine.state.selectedAdventureID() == currentAdventureID)

    let save = try repository.load()
    #expect(save.adventureID == currentAdventureID)
    #expect(save.player.position == currentPosition)
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

@Test func depthRaycasterSkipsWaterAndHitsRealOccluder() async throws {
    let map = [
        "######",
        "#.~..#",
        "######"
    ]

    let caster = DepthRaycaster(
        origin: DepthPoint(x: 1.5, y: 1.5),
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
    #expect(sample.hitTile.type == .wall)
    #expect(sample.hitPosition == Position(x: 5, y: 1))
    #expect(abs(sample.correctedDistance - 3.5) < 0.001)
}

@Test func depthTileSemanticsSeparateWaterFromWalls() async throws {
    #expect(TileFactory.tile(for: "#").type.blocksDepthRay)
    #expect(TileFactory.tile(for: "+").type.blocksDepthRay)
    #expect(TileFactory.tile(for: "+").type.blocksDepthLighting)
    #expect(TileFactory.tile(for: "~").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: "~").type.blocksDepthLighting == false)
    #expect(TileFactory.tile(for: "\"").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: "/").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: "*").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: ">").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: "B").type.blocksDepthRay == false)
    #expect(TileFactory.tile(for: "~").type.usesDepthPoolSurface)
    #expect(TileFactory.tile(for: "\"").type.usesDepthPoolSurface == false)
    #expect(TileFactory.tile(for: "/").type.usesDepthPoolSurface == false)
    #expect(TileFactory.tile(for: "*").type.usesDepthPoolSurface == false)
    #expect(TileFactory.tile(for: ">").type.usesDepthPoolSurface == false)
    #expect(TileFactory.tile(for: "B").type.usesDepthPoolSurface == false)
}

@Test func depthTileBillboardsOnlyAppearForPassThroughSceneryTiles() async throws {
    let floorCell = BoardCellSnapshot(position: Position(x: 0, y: 0), tile: TileFactory.tile(for: "."), occupant: .none, feature: .none)
    let wallCell = BoardCellSnapshot(position: Position(x: 1, y: 0), tile: TileFactory.tile(for: "#"), occupant: .none, feature: .none)
    let waterCell = BoardCellSnapshot(position: Position(x: 2, y: 0), tile: TileFactory.tile(for: "~"), occupant: .none, feature: .none)
    let brushCell = BoardCellSnapshot(position: Position(x: 3, y: 0), tile: TileFactory.tile(for: "\""), occupant: .none, feature: .none)
    let stairsCell = BoardCellSnapshot(position: Position(x: 4, y: 0), tile: TileFactory.tile(for: ">"), occupant: .none, feature: .none)
    let shrineCell = BoardCellSnapshot(position: Position(x: 5, y: 0), tile: TileFactory.tile(for: "*"), occupant: .none, feature: .none)
    let beaconCell = BoardCellSnapshot(position: Position(x: 6, y: 0), tile: TileFactory.tile(for: "B"), occupant: .none, feature: .none)
    let openDoorCell = BoardCellSnapshot(position: Position(x: 7, y: 0), tile: TileFactory.tile(for: "/"), occupant: .none, feature: .none)

    #expect(GraphicsSceneSnapshotBuilder.makeBillboard(for: floorCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0) == nil)
    #expect(GraphicsSceneSnapshotBuilder.makeBillboard(for: wallCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0) == nil)
    #expect(GraphicsSceneSnapshotBuilder.makeBillboard(for: waterCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0) == nil)
    #expect(isTileBillboard(GraphicsSceneSnapshotBuilder.makeBillboard(for: brushCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0), type: .brush))
    #expect(isTileBillboard(GraphicsSceneSnapshotBuilder.makeBillboard(for: stairsCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0), type: .stairs))
    #expect(isTileBillboard(GraphicsSceneSnapshotBuilder.makeBillboard(for: shrineCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0), type: .shrine))
    #expect(isTileBillboard(GraphicsSceneSnapshotBuilder.makeBillboard(for: beaconCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0), type: .beacon))
    #expect(isTileBillboard(GraphicsSceneSnapshotBuilder.makeBillboard(for: openDoorCell, distance: 1.0, angleOffset: 0.0, maxDistance: 18.0, lightLevel: 1.0), type: .doorOpen))
}

private func isTileBillboard(_ billboard: DepthBillboardSnapshot?, type: TileType) -> Bool {
    guard let billboard else {
        return false
    }
    guard case .tile(let billboardType) = billboard.kind else {
        return false
    }
    return billboardType.rawValue == type.rawValue
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
