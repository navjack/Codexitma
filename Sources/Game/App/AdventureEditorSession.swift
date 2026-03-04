import Foundation

enum AdventureEditorPanelFieldStyle {
    case value
    case action
}

struct AdventureEditorPanelField {
    let label: String
    let value: String
    let style: AdventureEditorPanelFieldStyle
}

struct AdventureEditorSceneSnapshot {
    let adventureID: String
    let title: String
    let folderName: String
    let currentMapID: String
    let currentMapName: String
    let mapLines: [String]
    let cursor: Position
    let selectedTool: EditorTool
    let selectedGlyph: Character
    let selectedContentTab: EditorContentTab
    let selectionSummaryLines: [String]
    let showsDocumentPanel: Bool
    let panelTitle: String
    let panelFields: [AdventureEditorPanelField]
    let panelSelectionIndex: Int
    let previewLines: [String]
    let validationMessages: [String]
    let statusLine: String
}

@MainActor
final class AdventureEditorSession {
    let store: AdventureEditorStore
    private(set) var cursor: Position
    private(set) var panelSelectionIndex = 0

    init(
        library: GameContentLibrary,
        initialAdventureID: AdventureID? = nil,
        exporter: AdventurePackExporter = AdventurePackExporter(),
        playtestLauncher: @MainActor @escaping (AdventureID) throws -> Void = AdventureEditorStore.defaultPlaytestLauncher
    ) {
        self.store = AdventureEditorStore(
            library: library,
            exporter: exporter,
            playtestLauncher: playtestLauncher
        )
        if let initialAdventureID {
            self.store.selectCatalogAdventure(initialAdventureID)
        }
        self.cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
    }

    var sceneSnapshot: AdventureEditorSceneSnapshot {
        let map = store.currentMap
        return AdventureEditorSceneSnapshot(
            adventureID: store.document.adventureID,
            title: store.document.title,
            folderName: store.document.folderName,
            currentMapID: map?.id ?? "",
            currentMapName: map?.name ?? "",
            mapLines: map?.lines ?? [],
            cursor: cursor,
            selectedTool: store.selectedTool,
            selectedGlyph: store.selectedGlyph,
            selectedContentTab: store.selectedContentTab,
            selectionSummaryLines: store.selectionSummaryLines,
            showsDocumentPanel: showsDocumentPanel,
            panelTitle: panelTitle,
            panelFields: panelFields,
            panelSelectionIndex: normalizedPanelSelectionIndex(for: panelFields),
            previewLines: previewLines,
            validationMessages: store.validationMessages,
            statusLine: store.statusLine
        )
    }

    func selectAdventure(_ adventureID: AdventureID) {
        store.selectCatalogAdventure(adventureID)
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        panelSelectionIndex = 0
        clampCursor()
    }

    func createBlankAdventure() {
        store.createBlankAdventure()
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        panelSelectionIndex = 0
        clampCursor()
    }

    func moveCursor(_ direction: Direction) {
        switch direction {
        case .up:
            cursor.y -= 1
        case .down:
            cursor.y += 1
        case .left:
            cursor.x -= 1
        case .right:
            cursor.x += 1
        }
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func setCursor(_ position: Position) {
        cursor = position
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func centerCursorOnSpawn() {
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func applyCurrentTool() {
        store.handleCanvasClick(x: cursor.x, y: cursor.y)
    }

    func cycleTool(step: Int = 1) {
        let tools = EditorTool.allCases
        guard let currentIndex = tools.firstIndex(of: store.selectedTool) else { return }
        let nextIndex = wrappedIndex(currentIndex + step, count: tools.count)
        store.selectTool(tools[nextIndex])
    }

    func cycleContentTab(step: Int = 1) {
        let tabs = EditorContentTab.allCases
        guard let currentIndex = tabs.firstIndex(of: store.selectedContentTab) else { return }
        let nextIndex = wrappedIndex(currentIndex + step, count: tabs.count)
        store.selectContentTab(tabs[nextIndex])
        panelSelectionIndex = 0
        normalizeSelectionForCurrentTab()
    }

    func cycleMap(step: Int = 1) {
        let count = store.document.maps.count
        guard count > 0 else { return }
        let nextIndex = wrappedIndex(store.document.selectedMapIndex + step, count: count)
        store.selectMap(index: nextIndex)
        centerCursorOnSpawn()
    }

    var showsDocumentPanel: Bool {
        store.selectedContentTab != .maps
    }

    func movePanelSelection(step: Int) {
        let fields = panelFields
        guard fields.isEmpty == false else { return }
        panelSelectionIndex = wrappedIndex(normalizedPanelSelectionIndex(for: fields) + step, count: fields.count)
    }

    func adjustSelectedField(step: Int) {
        switch store.selectedContentTab {
        case .maps:
            return
        case .dialogues:
            adjustDialogueField(step: step)
        case .questFlow:
            adjustQuestField(step: step)
        case .encounters:
            adjustEncounterField(step: step)
        case .shops:
            adjustShopField(step: step)
        case .npcs:
            adjustNPCField(step: step)
        case .enemies:
            adjustEnemyField(step: step)
        }
    }

    func activateSelectedField() {
        switch store.selectedContentTab {
        case .maps:
            return
        case .dialogues:
            switch normalizedPanelSelectionIndex(for: panelFields) {
            case 3:
                store.addDialogue()
            case 4:
                store.removeSelectedDialogue()
            default:
                break
            }
        case .questFlow:
            switch normalizedPanelSelectionIndex(for: panelFields) {
            case 3:
                store.addQuestStage()
            case 4:
                store.removeSelectedQuestStage()
            default:
                break
            }
        case .encounters:
            switch normalizedPanelSelectionIndex(for: panelFields) {
            case 3:
                store.addEncounter()
            case 4:
                store.removeSelectedEncounter()
            default:
                break
            }
        case .shops:
            switch normalizedPanelSelectionIndex(for: panelFields) {
            case 7:
                store.addShop()
            case 8:
                store.removeSelectedShop()
            case 9:
                store.addShopOffer()
            case 10:
                store.removeSelectedShopOffer()
            default:
                break
            }
        case .npcs:
            if normalizedPanelSelectionIndex(for: panelFields) == 3 {
                store.ensureShopForSelectedNPC()
            }
        case .enemies:
            break
        }
        normalizeSelectionForCurrentTab()
    }

    private func clampCursor() {
        guard let map = store.currentMap, let width = map.lines.first?.count, width > 0 else {
            cursor = Position(x: 0, y: 0)
            return
        }
        cursor.x = max(0, min(cursor.x, width - 1))
        cursor.y = max(0, min(cursor.y, map.lines.count - 1))
    }

    private func wrappedIndex(_ rawIndex: Int, count: Int) -> Int {
        let remainder = rawIndex % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private var panelTitle: String {
        switch store.selectedContentTab {
        case .maps:
            return "MAP CANVAS"
        case .dialogues:
            return "DIALOGUE NODES"
        case .questFlow:
            return "QUEST FLOW"
        case .encounters:
            return "ENCOUNTER TABLE"
        case .shops:
            return "MERCHANT LEDGER"
        case .npcs:
            return "NPC ROSTER"
        case .enemies:
            return "ENEMY ROSTER"
        }
    }

    private var panelFields: [AdventureEditorPanelField] {
        switch store.selectedContentTab {
        case .maps:
            return []
        case .dialogues:
            return dialogueFields()
        case .questFlow:
            return questFields()
        case .encounters:
            return encounterFields()
        case .shops:
            return shopFields()
        case .npcs:
            return npcFields()
        case .enemies:
            return enemyFields()
        }
    }

    private var previewLines: [String] {
        switch store.selectedContentTab {
        case .maps:
            return store.selectionSummaryLines
        case .dialogues:
            guard let dialogue = store.selectedDialogue else {
                return ["NO DIALOGUE SELECTED."]
            }
            return ["ID \(dialogue.id.uppercased())", "SPEAKER \(dialogue.speaker.uppercased())"] + dialogue.lines.map { $0.uppercased() }
        case .questFlow:
            let objective = store.selectedQuestStage?.objective.uppercased() ?? "NO QUEST STAGE."
            let flag = store.selectedQuestStage?.completeWhenFlag.rawValue.uppercased() ?? "NONE"
            return [objective, "FLAG \(flag)", store.document.questFlow.completionText.uppercased()]
        case .encounters:
            guard let encounter = store.selectedEncounter else {
                return ["NO ENCOUNTER SELECTED."]
            }
            return ["ID \(encounter.id.uppercased())", "ENEMY \(encounter.enemyID.uppercased())", encounter.introLine.uppercased()]
        case .shops:
            guard let shop = store.selectedShop else {
                return ["NO SHOP SELECTED."]
            }
            var lines = ["SHOP \(shop.id.uppercased())", "MERCHANT \(shop.merchantID.uppercased())", shop.introLine.uppercased()]
            if let offer = store.selectedShopOffer {
                lines.append("OFFER \(offer.id.uppercased()) \(offer.itemID.rawValue.uppercased()) \(offer.price)M")
                lines.append(offer.blurb.uppercased())
            }
            return lines
        case .npcs:
            guard let npc = store.selectedNPC ?? store.document.npcs.first else {
                return ["NO NPCS IN THIS PACK."]
            }
            return ["ID \(npc.id.uppercased())", "NAME \(npc.name.uppercased())", "DIALOGUE \(npc.dialogueID.uppercased())"]
        case .enemies:
            guard let enemy = store.selectedEnemy ?? store.document.enemies.first else {
                return ["NO ENEMIES IN THIS PACK."]
            }
            return [
                "ID \(enemy.id.uppercased())",
                "NAME \(enemy.name.uppercased())",
                "HP \(enemy.hp) ATK \(enemy.attack) DEF \(enemy.defense)",
                "AI \(enemy.ai.rawValue.uppercased())"
            ]
        }
    }

    private func normalizedPanelSelectionIndex(for fields: [AdventureEditorPanelField]) -> Int {
        guard fields.isEmpty == false else { return 0 }
        return max(0, min(panelSelectionIndex, fields.count - 1))
    }

    private func normalizeSelectionForCurrentTab() {
        switch store.selectedContentTab {
        case .npcs:
            if store.selectedNPC == nil, let first = store.document.npcs.first {
                store.focusNPC(id: first.id)
            }
        case .enemies:
            if store.selectedEnemy == nil, let first = store.document.enemies.first {
                store.focusEnemy(id: first.id)
            }
        case .shops:
            if store.selectedShop == nil, store.document.shops.isEmpty == false {
                store.selectShop(index: 0)
            }
        case .dialogues:
            if store.selectedDialogue == nil, store.document.dialogues.isEmpty == false {
                store.selectDialogue(index: 0)
            }
        case .questFlow:
            if store.selectedQuestStage == nil, store.document.questFlow.stages.isEmpty == false {
                store.selectQuestStage(index: 0)
            }
        case .encounters:
            if store.selectedEncounter == nil, store.document.encounters.isEmpty == false {
                store.selectEncounter(index: 0)
            }
        case .maps:
            break
        }
        panelSelectionIndex = normalizedPanelSelectionIndex(for: panelFields)
    }

    private func dialogueFields() -> [AdventureEditorPanelField] {
        let count = max(1, store.document.dialogues.count)
        let entry = AdventureEditorPanelField(
            label: "ENTRY",
            value: "\(store.selectedDialogueIndex + 1)/\(count)",
            style: .value
        )
        let speaker = AdventureEditorPanelField(
            label: "SPEAKER",
            value: store.selectedDialogue?.speaker.uppercased() ?? "NONE",
            style: .value
        )
        let lines = AdventureEditorPanelField(
            label: "LINES",
            value: "\(store.selectedDialogue?.lines.count ?? 0) BLOCK",
            style: .value
        )
        return [entry, speaker, lines,
                AdventureEditorPanelField(label: "ADD", value: "NEW NODE", style: .action),
                AdventureEditorPanelField(label: "REMOVE", value: "DELETE", style: .action)]
    }

    private func questFields() -> [AdventureEditorPanelField] {
        let count = max(1, store.document.questFlow.stages.count)
        let flag = store.selectedQuestStage?.completeWhenFlag.rawValue.uppercased() ?? "NONE"
        return [
            AdventureEditorPanelField(label: "STAGE", value: "\(store.selectedQuestStageIndex + 1)/\(count)", style: .value),
            AdventureEditorPanelField(label: "OBJECTIVE", value: "CYCLE TEXT", style: .value),
            AdventureEditorPanelField(label: "FLAG", value: flag, style: .value),
            AdventureEditorPanelField(label: "ADD", value: "NEW STAGE", style: .action),
            AdventureEditorPanelField(label: "REMOVE", value: "DELETE", style: .action)
        ]
    }

    private func encounterFields() -> [AdventureEditorPanelField] {
        let count = max(1, store.document.encounters.count)
        return [
            AdventureEditorPanelField(label: "ENTRY", value: "\(store.selectedEncounterIndex + 1)/\(count)", style: .value),
            AdventureEditorPanelField(label: "ENEMY", value: store.selectedEncounter?.enemyID.uppercased() ?? "NONE", style: .value),
            AdventureEditorPanelField(label: "INTRO", value: "CYCLE TEXT", style: .value),
            AdventureEditorPanelField(label: "ADD", value: "NEW ENCOUNTER", style: .action),
            AdventureEditorPanelField(label: "REMOVE", value: "DELETE", style: .action)
        ]
    }

    private func shopFields() -> [AdventureEditorPanelField] {
        let shopCount = max(1, store.document.shops.count)
        let offerCount = max(1, store.selectedShop?.offers.count ?? 0)
        let offer = store.selectedShopOffer
        return [
            AdventureEditorPanelField(label: "SHOP", value: "\(store.selectedShopIndex + 1)/\(shopCount)", style: .value),
            AdventureEditorPanelField(label: "MERCHANT", value: store.selectedShop?.merchantID.uppercased() ?? "NONE", style: .value),
            AdventureEditorPanelField(label: "INTRO", value: "CYCLE TEXT", style: .value),
            AdventureEditorPanelField(label: "OFFER", value: "\(store.selectedShopOfferIndex + 1)/\(offerCount)", style: .value),
            AdventureEditorPanelField(label: "ITEM", value: offer?.itemID.rawValue.uppercased() ?? "NONE", style: .value),
            AdventureEditorPanelField(label: "PRICE", value: "\(offer?.price ?? 0) MARKS", style: .value),
            AdventureEditorPanelField(label: "REPEAT", value: (offer?.repeatable ?? false) ? "YES" : "NO", style: .value),
            AdventureEditorPanelField(label: "ADD SHOP", value: "NEW LEDGER", style: .action),
            AdventureEditorPanelField(label: "REMOVE SHOP", value: "DELETE", style: .action),
            AdventureEditorPanelField(label: "ADD OFFER", value: "NEW ITEM", style: .action),
            AdventureEditorPanelField(label: "REMOVE OFFER", value: "DELETE", style: .action)
        ]
    }

    private func npcFields() -> [AdventureEditorPanelField] {
        let count = max(1, store.document.npcs.count)
        return [
            AdventureEditorPanelField(label: "NPC", value: "\(activeNPCIndex + 1)/\(count)", style: .value),
            AdventureEditorPanelField(label: "NAME", value: (store.selectedNPC?.name ?? store.document.npcs.first?.name ?? "NONE").uppercased(), style: .value),
            AdventureEditorPanelField(label: "DIALOGUE", value: (store.selectedNPC?.dialogueID ?? store.document.npcs.first?.dialogueID ?? "NONE").uppercased(), style: .value),
            AdventureEditorPanelField(label: "SHOP", value: "OPEN/CREATE", style: .action)
        ]
    }

    private func enemyFields() -> [AdventureEditorPanelField] {
        let count = max(1, store.document.enemies.count)
        let enemy = store.selectedEnemy ?? store.document.enemies.first
        return [
            AdventureEditorPanelField(label: "ENEMY", value: "\(activeEnemyIndex + 1)/\(count)", style: .value),
            AdventureEditorPanelField(label: "NAME", value: (enemy?.name ?? "NONE").uppercased(), style: .value),
            AdventureEditorPanelField(label: "HP", value: "\(enemy?.hp ?? 0)", style: .value),
            AdventureEditorPanelField(label: "ATK", value: "\(enemy?.attack ?? 0)", style: .value),
            AdventureEditorPanelField(label: "DEF", value: "\(enemy?.defense ?? 0)", style: .value),
            AdventureEditorPanelField(label: "AI", value: (enemy?.ai.rawValue.uppercased() ?? "NONE"), style: .value)
        ]
    }

    private var activeNPCIndex: Int {
        store.selectedNPCIndex ?? 0
    }

    private var activeEnemyIndex: Int {
        store.selectedEnemyIndex ?? 0
    }

    private func adjustDialogueField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let count = store.document.dialogues.count
            guard count > 0 else { return }
            store.selectDialogue(index: wrappedIndex(store.selectedDialogueIndex + step, count: count))
        case 1:
            let next = cycleValue(
                current: store.selectedDialogue?.speaker ?? "Guide",
                values: dialogueSpeakerTemplates,
                step: step
            )
            store.updateSelectedDialogueSpeaker(next)
        case 2:
            let current = store.selectedDialogue?.lines.joined(separator: "\n") ?? dialogueLineTemplates[0]
            let next = cycleValue(current: current, values: dialogueLineTemplates, step: step)
            store.updateSelectedDialogueLinesText(next)
        default:
            break
        }
    }

    private func adjustQuestField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let count = store.document.questFlow.stages.count
            guard count > 0 else { return }
            store.selectQuestStage(index: wrappedIndex(store.selectedQuestStageIndex + step, count: count))
        case 1:
            let next = cycleValue(
                current: store.selectedQuestStage?.objective ?? questObjectiveTemplates[0],
                values: questObjectiveTemplates,
                step: step
            )
            store.updateSelectedQuestObjective(next)
        case 2:
            let next = cycleValue(
                current: store.selectedQuestStage?.completeWhenFlag ?? .metElder,
                values: QuestFlag.allCases,
                step: step
            )
            store.updateSelectedQuestFlag(next)
        default:
            break
        }
    }

    private func adjustEncounterField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let count = store.document.encounters.count
            guard count > 0 else { return }
            store.selectEncounter(index: wrappedIndex(store.selectedEncounterIndex + step, count: count))
        case 1:
            let enemyIDs = store.document.enemies.map(\.id)
            guard enemyIDs.isEmpty == false else { return }
            let next = cycleValue(
                current: store.selectedEncounter?.enemyID ?? enemyIDs[0],
                values: enemyIDs,
                step: step
            )
            store.updateSelectedEncounterEnemyID(next)
        case 2:
            let next = cycleValue(
                current: store.selectedEncounter?.introLine ?? encounterIntroTemplates[0],
                values: encounterIntroTemplates,
                step: step
            )
            store.updateSelectedEncounterIntro(next)
        default:
            break
        }
    }

    private func adjustShopField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let count = store.document.shops.count
            guard count > 0 else { return }
            store.selectShop(index: wrappedIndex(store.selectedShopIndex + step, count: count))
        case 1:
            let merchantIDs = store.document.npcs.map(\.id)
            guard merchantIDs.isEmpty == false else { return }
            let next = cycleValue(
                current: store.selectedShop?.merchantID ?? merchantIDs[0],
                values: merchantIDs,
                step: step
            )
            store.updateSelectedShopMerchantID(next)
        case 2:
            let next = cycleValue(
                current: store.selectedShop?.introLine ?? shopIntroTemplates[0],
                values: shopIntroTemplates,
                step: step
            )
            store.updateSelectedShopIntro(next)
        case 3:
            guard let offerCount = store.selectedShop?.offers.count, offerCount > 0 else { return }
            store.selectShopOffer(index: wrappedIndex(store.selectedShopOfferIndex + step, count: offerCount))
        case 4:
            let next = cycleValue(
                current: store.selectedShopOffer?.itemID ?? .healingTonic,
                values: ItemID.allCases,
                step: step
            )
            store.updateSelectedShopOfferItemID(next)
        case 5:
            let current = store.selectedShopOffer?.price ?? 0
            store.updateSelectedShopOfferPrice(max(0, current + step))
        case 6:
            let current = store.selectedShopOffer?.repeatable ?? true
            store.updateSelectedShopOfferRepeatable(!current)
        default:
            break
        }
    }

    private func adjustNPCField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let npcs = store.document.npcs
            guard npcs.isEmpty == false else { return }
            let nextIndex = wrappedIndex(activeNPCIndex + step, count: npcs.count)
            store.focusNPC(id: npcs[nextIndex].id)
        case 1:
            let current = store.selectedNPC?.name ?? npcNameTemplates[0]
            let next = cycleValue(current: current, values: npcNameTemplates, step: step)
            store.updateSelectedNPCName(next)
        case 2:
            let dialogueIDs = store.document.dialogues.map(\.id)
            guard dialogueIDs.isEmpty == false else { return }
            let next = cycleValue(
                current: store.selectedNPC?.dialogueID ?? dialogueIDs[0],
                values: dialogueIDs,
                step: step
            )
            store.updateSelectedNPCDialogueID(next)
        default:
            break
        }
    }

    private func adjustEnemyField(step: Int) {
        switch normalizedPanelSelectionIndex(for: panelFields) {
        case 0:
            let enemies = store.document.enemies
            guard enemies.isEmpty == false else { return }
            let nextIndex = wrappedIndex(activeEnemyIndex + step, count: enemies.count)
            store.focusEnemy(id: enemies[nextIndex].id)
        case 1:
            let current = store.selectedEnemy?.name ?? enemyNameTemplates[0]
            let next = cycleValue(current: current, values: enemyNameTemplates, step: step)
            store.updateSelectedEnemyName(next)
        case 2:
            store.updateSelectedEnemyHP((store.selectedEnemy?.hp ?? 1) + step)
        case 3:
            store.updateSelectedEnemyAttack((store.selectedEnemy?.attack ?? 0) + step)
        case 4:
            store.updateSelectedEnemyDefense((store.selectedEnemy?.defense ?? 0) + step)
        case 5:
            let next = cycleValue(
                current: store.selectedEnemy?.ai ?? .idle,
                values: AIKind.allCases,
                step: step
            )
            store.updateSelectedEnemyAI(next)
        default:
            break
        }
    }

    private func cycleValue<T: Equatable>(current: T, values: [T], step: Int) -> T {
        guard values.isEmpty == false else { return current }
        let currentIndex = values.firstIndex(of: current) ?? 0
        return values[wrappedIndex(currentIndex + step, count: values.count)]
    }

    private let dialogueSpeakerTemplates = [
        "Guide",
        "Village Elder",
        "Fen Trader",
        "Beacon Warden",
        "Barrow Seer"
    ]

    private let dialogueLineTemplates = [
        "A fresh line waits to be written.",
        "The lamps are low, but the road is still open.",
        "The marsh remembers every footstep.",
        "The tower stirs when the runes align."
    ]

    private let questObjectiveTemplates = [
        "Define the next milestone.",
        "Reach the second landmark.",
        "Restore the hidden relay.",
        "Bring the core to the sealed gate."
    ]

    private let encounterIntroTemplates = [
        "A fresh threat enters the path.",
        "The brush splits and a shadow lunges.",
        "A cold hush falls before the strike.",
        "The chamber locks and the fight begins."
    ]

    private let shopIntroTemplates = [
        "A fresh ledger waits to be stocked.",
        "The merchant lays out a careful spread of goods.",
        "A low table offers tools for the next road.",
        "The trader watches your coin purse with quiet interest."
    ]

    private let npcNameTemplates = [
        "Guide Keeper",
        "Fen Broker",
        "Signal Archivist",
        "Lantern Porter",
        "Road Warden"
    ]

    private let enemyNameTemplates = [
        "Field Shade",
        "Gate Hound",
        "Fen Wraith",
        "Barrow Guard",
        "Rune Stalker"
    ]
}
