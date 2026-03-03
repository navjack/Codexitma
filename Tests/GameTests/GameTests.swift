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
            health: 10,
            maxHealth: 20,
            stamina: 5,
            maxStamina: 10,
            attack: 4,
            defense: 2,
            lanternCharge: 3,
            inventory: [],
            position: Position(x: 1, y: 1),
            currentMapID: "merrow_village",
            lastSavePosition: Position(x: 1, y: 1),
            lastSaveMapID: "merrow_village"
        ),
        world: WorldState(maps: [:], npcs: [], enemies: [], openedInteractables: [], activeSwitchSequence: []),
        quests: QuestState(flags: [.metElder]),
        playTimeSeconds: 42
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

@Test func screenBufferRendersExpectedLine() async throws {
    var buffer = ScreenBuffer(width: 8, height: 2)
    buffer.write("MERROW", x: 1, y: 0)
    #expect(buffer.line(0) == " MERROW ")
}

@Test func launchModeDefaultsToGraphicsButAllowsTerminalOverride() async throws {
    #expect(LaunchMode.parse(arguments: ["Game"]) == .graphics)
    #expect(LaunchMode.parse(arguments: ["Game", "--terminal"]) == .terminal)
}

@Test func contentLoaderLoadsSixMaps() async throws {
    let content = try ContentLoader().load()
    #expect(content.maps.count == 6)
}

@Test func automationTokenizerSplitsScriptsAndComments() async throws {
    let tokens = AutomationTokenizer.tokens(from: "new, right  # comment\nleft\nstate")
    #expect(tokens == ["new", "right", "left", "state"])
}

@Test func automationCommandParserRecognizesMovementAndState() async throws {
    #expect(try AutomationCommandParser.parse("a") == .game(.move(.left)))
    #expect(try AutomationCommandParser.parse("state") == .snapshot)
}

@Test func launchOptionsParseScriptMode() async throws {
    let options = try LaunchOptions.parse(arguments: ["Game", "--script", "new,right,e", "--step-json"])
    #expect(options.target == .script)
    #expect(options.commands == ["new", "right", "e"])
    #expect(options.emitStepSnapshots == true)
}
