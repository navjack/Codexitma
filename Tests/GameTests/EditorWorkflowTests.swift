import Foundation
import Testing
@testable import Game

@Test func editorStorePlacesLayeredObjectsAndSeedsDialogue() async throws {
    let library = try ContentLoader().load()
    let store = await MainActor.run {
        let store = AdventureEditorStore(library: library)
        store.createBlankAdventure()
        return store
    }

    await MainActor.run {
        let startingNPCCount = store.document.npcs.count
        let startingDialogueCount = store.document.dialogues.count
        let startingInteractableCount = store.document.maps[0].interactables.count

        store.selectTool(.npc)
        store.handleCanvasClick(x: 4, y: 4)

        #expect(store.document.npcs.count == startingNPCCount + 1)
        let placedNPC = store.document.npcs.last!
        #expect(placedNPC.position == Position(x: 4, y: 4))
        #expect(placedNPC.mapID == store.document.maps[0].id)
        #expect(store.document.dialogues.count == startingDialogueCount + 1)
        #expect(store.document.dialogues.contains(where: { $0.id == placedNPC.dialogueID }))

        store.selectTool(.interactable)
        store.selectedInteractableKind = .plate
        store.handleCanvasClick(x: 5, y: 4)

        #expect(store.document.maps[0].interactables.count == startingInteractableCount + 1)
        #expect(store.document.maps[0].interactables.last?.kind == .plate)
        #expect(store.selectedCanvasSelection?.position == Position(x: 5, y: 4))
    }
}

@Test func editorStoreRenamingMapsCascadesReferencesAndEraseRemovesObjects() async throws {
    let library = try ContentLoader().load()
    let store = await MainActor.run {
        let store = AdventureEditorStore(library: library)
        store.createBlankAdventure()
        return store
    }

    await MainActor.run {
        let startingNPCCount = store.document.npcs.count
        let startingEnemyCount = store.document.enemies.count
        store.selectTool(.npc)
        store.handleCanvasClick(x: 2, y: 2)

        store.selectTool(.enemy)
        store.handleCanvasClick(x: 4, y: 2)

        store.addMap()
        store.selectTool(.portal)
        store.handleCanvasClick(x: 2, y: 2)

        store.selectMap(index: 0)
        store.updateCurrentMapID("forge hall")

        #expect(store.document.maps[0].id == "forge_hall")
        #expect(store.document.npcs.last?.mapID == "forge_hall")
        #expect(store.document.enemies.last?.mapID == "forge_hall")
        #expect(store.document.maps[1].portals[0].toMap == "forge_hall")

        store.selectTool(.erase)
        store.handleCanvasClick(x: 2, y: 2)
        #expect(store.document.npcs.count == startingNPCCount)

        store.handleCanvasClick(x: 4, y: 2)
        #expect(store.document.enemies.count == startingEnemyCount)
    }
}

@Test func editorStoreInspectorMutatesSelectedObjects() async throws {
    let library = try ContentLoader().load()
    let store = await MainActor.run {
        let store = AdventureEditorStore(library: library)
        store.createBlankAdventure()
        return store
    }

    await MainActor.run {
        let startingNPCCount = store.document.npcs.count
        let startingEnemyCount = store.document.enemies.count
        let startingInteractableCount = store.document.maps[0].interactables.count

        store.selectTool(.npc)
        store.handleCanvasClick(x: 4, y: 4)
        store.updateSelectedNPCID("bazaar speaker")
        store.updateSelectedNPCName("Bazaar Speaker")
        store.updateSelectedNPCDialogueID("bazaar_intro")

        let editedNPC = store.document.npcs.last!
        #expect(store.document.npcs.count == startingNPCCount + 1)
        #expect(editedNPC.id == "bazaar_speaker")
        #expect(editedNPC.name == "Bazaar Speaker")
        #expect(editedNPC.dialogueID == "bazaar_intro")
        #expect(store.document.dialogues.contains(where: { $0.id == "bazaar_intro" }))

        store.selectTool(.enemy)
        store.handleCanvasClick(x: 5, y: 4)
        store.updateSelectedEnemyID("gate guard")
        store.updateSelectedEnemyName("Gate Guard")
        store.updateSelectedEnemyHP(14)
        store.updateSelectedEnemyAttack(6)
        store.updateSelectedEnemyDefense(4)
        store.updateSelectedEnemyAI(.guardian)

        let editedEnemy = store.document.enemies.last!
        #expect(store.document.enemies.count == startingEnemyCount + 1)
        #expect(editedEnemy.id == "gate_guard")
        #expect(editedEnemy.name == "Gate Guard")
        #expect(editedEnemy.hp == 14)
        #expect(editedEnemy.attack == 6)
        #expect(editedEnemy.defense == 4)
        #expect(editedEnemy.ai == .guardian)

        store.selectTool(.interactable)
        store.handleCanvasClick(x: 7, y: 4)
        store.updateSelectedInteractableID("signal plate")
        store.updateSelectedInteractableTitle("Signal Plate")
        store.updateSelectedInteractableKind(.switchRune)
        store.updateSelectedInteractableRewardItem(.lanternOil)
        store.updateSelectedInteractableRewardMarks(12)
        store.updateSelectedInteractableRequiredFlag(.metElder)
        store.updateSelectedInteractableGrantsFlag(.fenCrossed)

        let editedInteractable = store.document.maps[0].interactables.last!
        #expect(store.document.maps[0].interactables.count == startingInteractableCount + 1)
        #expect(editedInteractable.id == "signal_plate")
        #expect(editedInteractable.title == "Signal Plate")
        #expect(editedInteractable.kind == .switchRune)
        #expect(editedInteractable.rewardItem == .lanternOil)
        #expect(editedInteractable.rewardMarks == 12)
        #expect(editedInteractable.requiredFlag == .metElder)
        #expect(editedInteractable.grantsFlag == .fenCrossed)
    }
}

@Test func blankEditorTemplateSeedsUsableStarterContent() async throws {
    let library = try ContentLoader().load()
    let store = await MainActor.run {
        let store = AdventureEditorStore(library: library)
        store.createBlankAdventure()
        return store
    }

    await MainActor.run {
        #expect(store.document.dialogues.isEmpty == false)
        #expect(store.document.encounters.isEmpty == false)
        #expect(store.document.npcs.isEmpty == false)
        #expect(store.document.enemies.isEmpty == false)
        #expect(store.document.shops.isEmpty == false)
        #expect(store.document.maps[0].interactables.isEmpty == false)
        #expect(store.document.shops[0].merchantID == store.document.npcs[0].id)
    }
}

@Test func adventureEditorSessionBuildsRendererNeutralSnapshot() async throws {
    let library = try ContentLoader().load()
    let session = await MainActor.run {
        let session = AdventureEditorSession(library: library)
        session.createBlankAdventure()
        return session
    }

    await MainActor.run {
        let initial = session.sceneSnapshot
        #expect(initial.mapLines.isEmpty == false)
        #expect(initial.selectedTool == .terrain)
        #expect(initial.currentMapID == "merrow_village")

        session.cycleTool()
        #expect(session.sceneSnapshot.selectedTool == .npc)

        session.setCursor(Position(x: 4, y: 4))
        session.applyCurrentTool()

        let snapshot = session.sceneSnapshot
        #expect(snapshot.cursor == Position(x: 4, y: 4))
        #expect(snapshot.selectionSummaryLines.first?.contains("NPC") == true)
        #expect(snapshot.statusLine.contains("PLACED NPC"))
    }
}

@Test func adventureEditorSessionSupportsDocumentTabEditing() async throws {
    let library = try ContentLoader().load()
    let session = await MainActor.run {
        let session = AdventureEditorSession(library: library)
        session.createBlankAdventure()
        return session
    }

    await MainActor.run {
        session.cycleContentTab()
        #expect(session.showsDocumentPanel)
        #expect(session.sceneSnapshot.selectedContentTab == .dialogues)
        #expect(session.sceneSnapshot.panelFields.isEmpty == false)

        let originalSpeaker = session.store.selectedDialogue?.speaker
        session.movePanelSelection(step: 1)
        session.adjustSelectedField(step: 1)
        #expect(session.store.selectedDialogue?.speaker != originalSpeaker)

        session.cycleContentTab()
        #expect(session.sceneSnapshot.selectedContentTab == .questFlow)
        let originalFlag = session.store.selectedQuestStage?.completeWhenFlag
        session.movePanelSelection(step: 2)
        session.adjustSelectedField(step: 1)
        #expect(session.store.selectedQuestStage?.completeWhenFlag != originalFlag)
    }
}

@Test func editorStoreDataEditorsMutateDialogueQuestEncounterAndShopContent() async throws {
    let library = try ContentLoader().load()
    let store = await MainActor.run {
        let store = AdventureEditorStore(library: library)
        store.createBlankAdventure()
        return store
    }

    await MainActor.run {
        store.addDialogue()
        store.updateSelectedDialogueID("camp rumor")
        store.updateSelectedDialogueSpeaker("Camp Rumor")
        store.updateSelectedDialogueLinesText("First line\nSecond line")
        #expect(store.selectedDialogue?.id == "camp_rumor")
        #expect(store.selectedDialogue?.speaker == "Camp Rumor")
        #expect(store.selectedDialogue?.lines == ["First line", "Second line"])

        store.addQuestStage()
        store.updateSelectedQuestObjective("Reach the second lantern.")
        store.updateSelectedQuestFlag(.fenCrossed)
        store.updateQuestCompletionText("A longer road now opens.")
        #expect(store.selectedQuestStage?.objective == "Reach the second lantern.")
        #expect(store.selectedQuestStage?.completeWhenFlag == .fenCrossed)
        #expect(store.document.questFlow.completionText == "A longer road now opens.")

        store.addEncounter()
        store.updateSelectedEncounterID("fen ambush")
        store.updateSelectedEncounterEnemyID("field_shade")
        store.updateSelectedEncounterIntro("The reeds split and the ambush begins.")
        #expect(store.selectedEncounter?.id == "fen_ambush")
        #expect(store.selectedEncounter?.enemyID == "field_shade")
        #expect(store.selectedEncounter?.introLine == "The reeds split and the ambush begins.")

        store.focusNPC(id: store.document.npcs[0].id)
        store.ensureShopForSelectedNPC()
        #expect(store.selectedContentTab == .shops)

        store.updateSelectedShopID("traveling stock")
        store.updateSelectedShopMerchantID(store.document.npcs[0].id)
        store.updateSelectedShopIntro("A longer trade script.")
        store.addShopOffer()
        store.updateSelectedShopOfferID("lantern crate")
        store.updateSelectedShopOfferItemID(.lanternOil)
        store.updateSelectedShopOfferPrice(5)
        store.updateSelectedShopOfferBlurb("Enough oil for a long descent.")
        store.updateSelectedShopOfferRepeatable(false)

        #expect(store.selectedShop?.id == "traveling_stock")
        #expect(store.selectedShop?.merchantID == store.document.npcs[0].id)
        #expect(store.selectedShop?.introLine == "A longer trade script.")
        #expect(store.selectedShop?.offers.last?.id == "lantern_crate")
        #expect(store.selectedShop?.offers.last?.itemID == .lanternOil)
        #expect(store.selectedShop?.offers.last?.price == 5)
        #expect(store.selectedShop?.offers.last?.repeatable == false)
    }
}

@MainActor
@Test func editorStoreSaveAndPlaytestExportsAndLaunchesSelectedAdventure() async throws {
    let library = try ContentLoader().load()
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let exporter = AdventurePackExporter(externalRootURL: root)
    var launchedAdventure: AdventureID?

    let store = AdventureEditorStore(
        library: library,
        exporter: exporter,
        playtestLauncher: { adventureID in
            launchedAdventure = adventureID
        }
    )
    store.createBlankAdventure()
    store.updateAdventureID("editorPlaytest")
    store.updateFolderName("editor_playtest")

    store.saveAndPlaytestCurrentPack()
    #expect(launchedAdventure == AdventureID(rawValue: "editorplaytest"))
    let packURL = root.appendingPathComponent("editor_playtest", isDirectory: true)
    #expect(FileManager.default.fileExists(atPath: packURL.appendingPathComponent("adventure.json").path))
}

@Test func interactableRewardMarksIncreasePlayerCurrency() async throws {
    let library = try ContentLoader().load()
    let saveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    let engine = GameEngine(library: library, saveRepository: SaveRepository(fileURL: saveURL))

    engine.handle(.newGame)
    engine.handle(.confirm)
    engine.state.world.npcs = []
    engine.state.world.enemies = []

    let mapID = engine.state.player.currentMapID
    var map = try #require(engine.state.world.maps[mapID])
    let interactable = InteractableDefinition(
        id: "coin_cache",
        kind: .chest,
        position: engine.state.player.position,
        title: "Coin Cache",
        lines: ["Loose marks spill into your hands."],
        rewardItem: nil,
        rewardMarks: 7,
        requiredFlag: nil,
        grantsFlag: nil
    )
    map = MapDefinition(
        id: map.id,
        name: map.name,
        layoutFile: map.layoutFile,
        lines: map.lines,
        spawn: map.spawn,
        portals: map.portals,
        interactables: map.interactables + [interactable]
    )
    engine.state.world.maps[mapID] = map

    let marksBefore = engine.state.player.marks
    engine.handle(.interact)

    #expect(engine.state.player.marks == marksBefore + 7)
    #expect(engine.state.world.openedInteractables.contains("coin_cache"))
}

@Test func adventurePackExporterValidationCatchesBrokenReferences() async throws {
    let exporter = AdventurePackExporter(
        externalRootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    let document = EditableAdventureDocument(
        folderName: "broken_pack",
        adventureID: "brokenPack",
        title: "Broken Pack",
        summary: "A deliberately invalid pack.",
        introLine: "Nothing lines up.",
        maps: [
            EditableMap(
                id: "merrow_village",
                name: "Broken Grounds",
                lines: [
                    "#####",
                    "#...#",
                    "#####"
                ],
                spawn: Position(x: 9, y: 9),
                portals: [
                    Portal(
                        from: Position(x: 1, y: 1),
                        toMap: "missing_map",
                        toPosition: Position(x: 0, y: 0),
                        requiredFlag: .metElder,
                        blockedMessage: nil
                    )
                ],
                interactables: []
            )
        ],
        selectedMapIndex: 0,
        questFlow: QuestFlowDefinition(
            stages: [QuestStageDefinition(objective: "Find a path.", completeWhenFlag: .metElder)],
            completionText: "Done."
        ),
        dialogues: [DialogueNode(id: "intro", speaker: "Guide", lines: ["Hello"])],
        encounters: [EncounterDefinition(id: "bad_encounter", enemyID: "missing_enemy", introLine: "Oops")],
        npcs: [
            NPCState(
                id: "guide",
                name: "Guide",
                position: Position(x: 1, y: 1),
                mapID: "merrow_village",
                dialogueID: "missing_dialogue",
                glyphSymbol: "&",
                glyphColor: .yellow,
                dialogueState: 0
            )
        ],
        enemies: [],
        shops: []
    )

    let issues = exporter.validate(document: document)
    #expect(issues.contains(where: { $0.contains("spawn outside") }))
    #expect(issues.contains(where: { $0.contains("missing map") }))
    #expect(issues.contains(where: { $0.contains("missing dialogue") }))
    #expect(issues.contains(where: { $0.contains("needs blocked text") }))
    #expect(issues.contains(where: { $0.contains("missing enemy") }))
    #expect(throws: AdventurePackValidationError.self) {
        try exporter.save(document: document)
    }
}
