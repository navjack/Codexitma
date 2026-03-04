import AppKit
import Foundation
import SwiftUI

@MainActor
final class AdventureEditorStore: ObservableObject {
    @Published var selectedCatalogID: AdventureID?
    @Published var document: EditableAdventureDocument
    @Published var selectedContentTab: EditorContentTab = .maps
    @Published var selectedTool: EditorTool = .terrain
    @Published var selectedGlyph: Character = "#"
    @Published var selectedInteractableKind: InteractableKind = .chest
    @Published var selectedCanvasSelection: EditorCanvasSelection?
    @Published var selectedDialogueIndex = 0
    @Published var selectedQuestStageIndex = 0
    @Published var selectedEncounterIndex = 0
    @Published var selectedShopIndex = 0
    @Published var selectedShopOfferIndex = 0
    @Published var validationMessages: [String] = []
    @Published var statusLine = "READY. FORK AN ADVENTURE OR CREATE A NEW TEMPLATE."

    let catalog: [AdventureCatalogEntry]

    private let library: GameContentLibrary
    private let exporter: AdventurePackExporter
    private let playtestLauncher: @MainActor (AdventureID) throws -> Void

    init(
        library: GameContentLibrary,
        exporter: AdventurePackExporter = AdventurePackExporter(),
        playtestLauncher: @MainActor @escaping (AdventureID) throws -> Void = AdventureEditorStore.defaultPlaytestLauncher
    ) {
        self.library = library
        self.catalog = library.catalog
        self.exporter = exporter
        self.playtestLauncher = playtestLauncher

        if let first = library.catalog.first {
            self.selectedCatalogID = first.id
            self.document = Self.makeDocument(
                entry: first,
                content: library.content(for: first.id)
            )
            self.statusLine = "READY. \(first.title.uppercased()) IS LOADED INTO THE EDITOR."
        } else {
            self.document = Self.makeBlankDocument()
        }
    }

    var currentMap: EditableMap? {
        guard !document.maps.isEmpty else { return nil }
        let index = max(0, min(document.selectedMapIndex, document.maps.count - 1))
        return document.maps[index]
    }

    var currentMapID: String? {
        currentMap?.id
    }

    var selectedToolSummary: String {
        "\(selectedTool.title.uppercased()): \(selectedTool.helpText.uppercased())"
    }

    var selectionSummaryLines: [String] {
        guard let selection = selectedCanvasSelection,
              let map = currentMap else {
            return [
                "NO ACTIVE SELECTION",
                "USE SELECT TO INSPECT OR PLACE A NEW OBJECT."
            ]
        }

        switch selection.kind {
        case .tile:
            let glyph = glyphAt(selection.position, in: map)
            let tile = TileFactory.tile(for: glyph)
            return [
                "TILE \(selection.position.x),\(selection.position.y)",
                "GLYPH \(displayGlyph(glyph))",
                "TYPE \(tileTypeLabel(tile.type))"
            ]
        case .spawn:
            return [
                "SPAWN POINT",
                "MAP \(map.id)",
                "AT \(selection.position.x),\(selection.position.y)"
            ]
        case .npc(let id):
            guard let npc = document.npcs.first(where: { $0.id == id }) else {
                return ["NPC \(id.uppercased())", "NO LONGER PRESENT"]
            }
            return [
                "NPC \(npc.name.uppercased())",
                "ID \(npc.id)",
                "DIALOGUE \(npc.dialogueID)"
            ]
        case .enemy(let id):
            guard let enemy = document.enemies.first(where: { $0.id == id }) else {
                return ["ENEMY \(id.uppercased())", "NO LONGER PRESENT"]
            }
            return [
                "ENEMY \(enemy.name.uppercased())",
                "ID \(enemy.id)",
                "HP \(enemy.hp)  ATK \(enemy.attack)  DEF \(enemy.defense)"
            ]
        case .interactable(let id):
            guard let interactable = map.interactables.first(where: { $0.id == id }) else {
                return ["INTERACTABLE \(id.uppercased())", "NO LONGER PRESENT"]
            }
            return [
                "INTERACTABLE \(interactable.id.uppercased())",
                "KIND \(interactable.kind.rawValue.uppercased())",
                interactable.title.uppercased()
            ]
        case .portal(let index):
            guard index >= 0, index < map.portals.count else {
                return ["PORTAL", "NO LONGER PRESENT"]
            }
            let portal = map.portals[index]
            return [
                "PORTAL AT \(portal.from.x),\(portal.from.y)",
                "TO \(portal.toMap)",
                "DEST \(portal.toPosition.x),\(portal.toPosition.y)"
            ]
        }
    }

    var currentMapCountsLine: String {
        guard let map = currentMap else { return "NO MAP" }
        let mapID = map.id
        let npcCount = document.npcs.filter { $0.mapID == mapID }.count
        let enemyCount = document.enemies.filter { $0.mapID == mapID }.count
        let interactableCount = map.interactables.count
        let portalCount = map.portals.count
        return "NPC \(npcCount)  ENM \(enemyCount)  INT \(interactableCount)  PORT \(portalCount)"
    }

    var selectedNPC: NPCState? {
        guard case .npc(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.npcs.first(where: { $0.id == id })
    }

    var selectedEnemy: EnemyState? {
        guard case .enemy(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.enemies.first(where: { $0.id == id })
    }

    var selectedInteractable: InteractableDefinition? {
        guard case .interactable(let id) = selectedCanvasSelection?.kind else { return nil }
        return currentMap?.interactables.first(where: { $0.id == id })
    }

    var selectedPortal: Portal? {
        guard case .portal(let index) = selectedCanvasSelection?.kind,
              let map = currentMap,
              index >= 0,
              index < map.portals.count else {
            return nil
        }
        return map.portals[index]
    }

    var selectedDialogue: DialogueNode? {
        guard !document.dialogues.isEmpty else { return nil }
        let index = max(0, min(selectedDialogueIndex, document.dialogues.count - 1))
        return document.dialogues[index]
    }

    var selectedQuestStage: QuestStageDefinition? {
        guard !document.questFlow.stages.isEmpty else { return nil }
        let index = max(0, min(selectedQuestStageIndex, document.questFlow.stages.count - 1))
        return document.questFlow.stages[index]
    }

    var selectedEncounter: EncounterDefinition? {
        guard !document.encounters.isEmpty else { return nil }
        let index = max(0, min(selectedEncounterIndex, document.encounters.count - 1))
        return document.encounters[index]
    }

    var selectedShop: ShopDefinition? {
        guard !document.shops.isEmpty else { return nil }
        let index = max(0, min(selectedShopIndex, document.shops.count - 1))
        return document.shops[index]
    }

    var selectedShopOffer: ShopOffer? {
        guard let shop = selectedShop, !shop.offers.isEmpty else { return nil }
        let index = max(0, min(selectedShopOfferIndex, shop.offers.count - 1))
        return shop.offers[index]
    }

    var savePolicyLines: [String] {
        guard let adventureID = selectedCatalogID,
              let entry = library.entry(for: adventureID) else {
            return [
                "SOURCE: NEW CUSTOM PACK",
                "SAVE WRITES A BRAND NEW USER ADVENTURE IN APPLICATION SUPPORT."
            ]
        }

        if entry.folder.contains("/") {
            return [
                "SOURCE: USER PACK OR OVERRIDE",
                "SAVE WRITES BACK INTO THE EXISTING EXTERNAL PACK FOLDER."
            ]
        }

        return [
            "SOURCE: BUNDLED ADVENTURE",
            "SAVE WRITES A SAFE EXTERNAL OVERRIDE. THE APP BUNDLE IS NEVER MODIFIED."
        ]
    }

    var selectedNPCShop: ShopDefinition? {
        guard let npc = selectedNPC else { return nil }
        return document.shops.first(where: { $0.merchantID == npc.id })
    }

    func selectCatalogAdventure(_ adventureID: AdventureID) {
        selectedCatalogID = adventureID
        let entry = library.entry(for: adventureID) ?? AdventureCatalogEntry(
            id: adventureID,
            folder: adventureID.rawValue,
            packFile: "adventure.json",
            title: adventureID.rawValue,
            summary: "",
            introLine: ""
        )
        document = Self.makeDocument(entry: entry, content: library.content(for: adventureID))
        resetSecondarySelections()
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        validationMessages = []
        statusLine = "LOADED \(entry.title.uppercased()) FOR EDITING."
    }

    func createBlankAdventure() {
        selectedCatalogID = nil
        document = Self.makeBlankDocument()
        resetSecondarySelections()
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        validationMessages = []
        statusLine = "BLANK TEMPLATE CREATED. SAVE IT TO EXPORT A NEW ADVENTURE PACK."
    }

    @discardableResult
    func validateCurrentPack() -> Bool {
        let issues = exporter.validate(document: document)
        validationMessages = issues
        if issues.isEmpty {
            statusLine = "VALIDATION CLEAN. THE PACK IS READY TO EXPORT."
            return true
        }
        statusLine = "VALIDATION FAILED: \(issues.count) ISSUE(S)."
        return false
    }

    func saveCurrentPack() {
        guard validateCurrentPack() else { return }
        do {
            let exportedURL = try exporter.save(document: document)
            statusLine = "EXPORTED TO \(exportedURL.path.uppercased())"
        } catch {
            statusLine = "EXPORT FAILED: \(String(describing: error).uppercased())"
        }
    }

    func saveAndPlaytestCurrentPack() {
        guard validateCurrentPack() else { return }
        do {
            _ = try exporter.save(document: document)
            try playtestLauncher(AdventureID(rawValue: document.adventureID))
            statusLine = "PLAYTEST LAUNCHED FOR \(document.title.uppercased())."
        } catch {
            statusLine = "PLAYTEST FAILED: \(String(describing: error).uppercased())"
        }
    }

    func selectContentTab(_ tab: EditorContentTab) {
        selectedContentTab = tab
        statusLine = "\(tab.title.uppercased()) TAB READY."
    }

    func selectMap(index: Int) {
        guard !document.maps.isEmpty else { return }
        document.selectedMapIndex = max(0, min(index, document.maps.count - 1))
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        statusLine = "EDITING \(document.maps[document.selectedMapIndex].name.uppercased())."
    }

    func addMap() {
        let nextIndex = document.maps.count + 1
        let newMap = EditableMap(
            id: "new_map_\(nextIndex)",
            name: "New Map \(nextIndex)",
            lines: Self.makeStarterMapLines(),
            spawn: Position(x: 2, y: 2),
            portals: [],
            interactables: []
        )
        document.maps.append(newMap)
        document.selectedMapIndex = document.maps.count - 1
        statusLine = "ADDED \(newMap.name.uppercased())."
    }

    func duplicateSelectedMap() {
        guard let map = currentMap else { return }
        let duplicate = EditableMap(
            id: "\(map.id)_copy",
            name: "\(map.name) Copy",
            lines: map.lines,
            spawn: map.spawn,
            portals: map.portals,
            interactables: map.interactables
        )
        let insertIndex = min(document.selectedMapIndex + 1, document.maps.count)
        document.maps.insert(duplicate, at: insertIndex)
        document.selectedMapIndex = insertIndex
        statusLine = "DUPLICATED \(map.name.uppercased())."
    }

    func updateFolderName(_ value: String) {
        document.folderName = sanitizeFolderName(value)
    }

    func updateAdventureID(_ value: String) {
        document.adventureID = sanitizeIdentifier(value)
    }

    func updateTitle(_ value: String) {
        document.title = value
    }

    func updateSummary(_ value: String) {
        document.summary = value
    }

    func updateIntroLine(_ value: String) {
        document.introLine = value
    }

    func updateCurrentMapID(_ value: String) {
        guard !document.maps.isEmpty else { return }
        let oldID = document.maps[document.selectedMapIndex].id
        let newID = sanitizeIdentifier(value)
        document.maps[document.selectedMapIndex].id = newID
        if oldID != newID {
            for index in document.npcs.indices where document.npcs[index].mapID == oldID {
                document.npcs[index].mapID = newID
            }
            for index in document.enemies.indices where document.enemies[index].mapID == oldID {
                document.enemies[index].mapID = newID
            }
            for mapIndex in document.maps.indices {
                for portalIndex in document.maps[mapIndex].portals.indices {
                    if document.maps[mapIndex].portals[portalIndex].toMap == oldID {
                        let portal = document.maps[mapIndex].portals[portalIndex]
                        document.maps[mapIndex].portals[portalIndex] = Portal(
                            from: portal.from,
                            toMap: newID,
                            toPosition: portal.toPosition,
                            requiredFlag: portal.requiredFlag,
                            blockedMessage: portal.blockedMessage
                        )
                    }
                }
            }
        }
    }

    func updateCurrentMapName(_ value: String) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].name = value
    }

    func paintTile(x: Int, y: Int) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].setGlyph(selectedGlyph, atX: x, y: y)
        selectedCanvasSelection = EditorCanvasSelection(kind: .tile, position: Position(x: x, y: y))
        statusLine = "PAINTED \(displayGlyph(selectedGlyph)) AT \(x),\(y)."
    }

    func selectTool(_ tool: EditorTool) {
        selectedTool = tool
        statusLine = "\(tool.title.uppercased()) TOOL READY. \(tool.helpText.uppercased())"
    }

    func handleCanvasClick(x: Int, y: Int) {
        let position = Position(x: x, y: y)
        switch selectedTool {
        case .terrain:
            paintTile(x: x, y: y)
        case .npc:
            placeNPC(at: position)
        case .enemy:
            placeEnemy(at: position)
        case .interactable:
            placeInteractable(at: position)
        case .portal:
            placePortal(at: position)
        case .spawn:
            setSpawn(at: position)
        case .erase:
            erase(at: position)
        case .select:
            selectCanvasObject(at: position)
        }
    }

    func overlay(atX x: Int, y: Int) -> EditorCanvasOverlay? {
        guard let mapID = currentMapID else { return nil }
        let position = Position(x: x, y: y)

        if let npc = document.npcs.first(where: { $0.mapID == mapID && $0.position == position }) {
            return EditorCanvasOverlay(glyph: String(npc.glyphSymbol), fill: color(for: npc.glyphColor), text: .black)
        }

        if let enemy = document.enemies.first(where: { $0.mapID == mapID && $0.position == position }) {
            return EditorCanvasOverlay(glyph: String(enemy.glyph), fill: color(for: enemy.color), text: .black)
        }

        if let interactable = currentMap?.interactables.first(where: { $0.position == position }) {
            return EditorCanvasOverlay(
                glyph: interactableGlyph(for: interactable.kind),
                fill: color(for: interactable.kind),
                text: .black
            )
        }

        if currentMap?.portals.contains(where: { $0.from == position }) == true {
            return EditorCanvasOverlay(glyph: ">", fill: Color(red: 0.98, green: 0.82, blue: 0.20), text: .black)
        }

        if currentMap?.spawn == position {
            return EditorCanvasOverlay(glyph: "@", fill: Color(red: 0.98, green: 0.95, blue: 0.62), text: .black)
        }

        return nil
    }

    func isSelected(x: Int, y: Int) -> Bool {
        selectedCanvasSelection?.position == Position(x: x, y: y)
    }

    func isSpawn(x: Int, y: Int) -> Bool {
        currentMap?.spawn == Position(x: x, y: y)
    }

    func updateSelectedNPCID(_ value: String) {
        guard case .npc(let oldID) = selectedCanvasSelection?.kind,
              let index = document.npcs.firstIndex(where: { $0.id == oldID }) else {
            return
        }
        let newID = nextIdentifier(prefix: value, existing: document.npcs.enumerated().compactMap { offset, npc in
            offset == index ? nil : npc.id
        })
        let npc = document.npcs[index]
        document.npcs[index] = NPCState(
            id: newID,
            name: npc.name,
            position: npc.position,
            mapID: npc.mapID,
            dialogueID: npc.dialogueID,
            glyphSymbol: npc.glyphSymbol,
            glyphColor: npc.glyphColor,
            dialogueState: npc.dialogueState
        )
        document.shops = document.shops.map { shop in
            guard shop.merchantID == oldID else { return shop }
            return ShopDefinition(
                id: shop.id,
                merchantID: newID,
                merchantName: shop.merchantName,
                introLine: shop.introLine,
                offers: shop.offers
            )
        }
        selectedCanvasSelection = EditorCanvasSelection(kind: .npc(id: newID), position: npc.position)
    }

    func updateSelectedNPCName(_ value: String) {
        guard let index = selectedNPCIndex else { return }
        document.npcs[index].name = value
        for shopIndex in document.shops.indices where document.shops[shopIndex].merchantID == document.npcs[index].id {
            document.shops[shopIndex] = ShopDefinition(
                id: document.shops[shopIndex].id,
                merchantID: document.shops[shopIndex].merchantID,
                merchantName: value,
                introLine: document.shops[shopIndex].introLine,
                offers: document.shops[shopIndex].offers
            )
        }
    }

    func updateSelectedNPCDialogueID(_ value: String) {
        guard let index = selectedNPCIndex else { return }
        let newID = sanitizeIdentifier(value)
        document.npcs[index].dialogueID = newID
        if !document.dialogues.contains(where: { $0.id == newID }) {
            document.dialogues.append(
                DialogueNode(
                    id: newID,
                    speaker: document.npcs[index].name,
                    lines: ["A placeholder dialogue waits for its final script."]
                )
            )
        }
    }

    func updateSelectedEnemyID(_ value: String) {
        guard case .enemy(let oldID) = selectedCanvasSelection?.kind,
              let index = document.enemies.firstIndex(where: { $0.id == oldID }) else {
            return
        }
        let newID = nextIdentifier(prefix: value, existing: document.enemies.enumerated().compactMap { offset, enemy in
            offset == index ? nil : enemy.id
        })
        let enemy = document.enemies[index]
        document.enemies[index] = EnemyState(
            id: newID,
            name: enemy.name,
            position: enemy.position,
            hp: enemy.hp,
            maxHP: max(enemy.maxHP, enemy.hp),
            attack: enemy.attack,
            defense: enemy.defense,
            ai: enemy.ai,
            glyph: enemy.glyph,
            color: enemy.color,
            mapID: enemy.mapID,
            active: enemy.active
        )
        selectedCanvasSelection = EditorCanvasSelection(kind: .enemy(id: newID), position: enemy.position)
    }

    func updateSelectedEnemyName(_ value: String) {
        guard let index = selectedEnemyIndex else { return }
        document.enemies[index].name = value
    }

    func updateSelectedEnemyHP(_ value: Int) {
        guard let index = selectedEnemyIndex else { return }
        let clamped = max(1, value)
        document.enemies[index].hp = clamped
        document.enemies[index].maxHP = max(document.enemies[index].maxHP, clamped)
    }

    func updateSelectedEnemyAttack(_ value: Int) {
        guard let index = selectedEnemyIndex else { return }
        document.enemies[index].attack = max(0, value)
    }

    func updateSelectedEnemyDefense(_ value: Int) {
        guard let index = selectedEnemyIndex else { return }
        document.enemies[index].defense = max(0, value)
    }

    func updateSelectedEnemyAI(_ ai: AIKind) {
        guard let index = selectedEnemyIndex else { return }
        document.enemies[index].ai = ai
    }

    func updateSelectedInteractableID(_ value: String) {
        guard case .interactable(let oldID) = selectedCanvasSelection?.kind,
              let index = selectedInteractableIndex else {
            return
        }
        let newID = nextIdentifier(
            prefix: value,
            existing: document.maps
                .flatMap { $0.interactables.map(\.id) }
                .filter { $0 != oldID }
        )
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: newID,
            kind: interactable.kind,
            position: interactable.position,
            title: interactable.title,
            lines: interactable.lines,
            rewardItem: interactable.rewardItem,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: interactable.grantsFlag
        )
        selectedCanvasSelection = EditorCanvasSelection(kind: .interactable(id: newID), position: interactable.position)
    }

    func updateSelectedInteractableTitle(_ value: String) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: interactable.kind,
            position: interactable.position,
            title: value,
            lines: interactable.lines,
            rewardItem: interactable.rewardItem,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: interactable.grantsFlag
        )
    }

    func updateSelectedInteractableKind(_ kind: InteractableKind) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: kind,
            position: interactable.position,
            title: interactable.title,
            lines: kind.defaultLines,
            rewardItem: kind == .chest ? .healingTonic : nil,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: interactable.grantsFlag
        )
        selectedInteractableKind = kind
    }

    func updateSelectedInteractableRewardItem(_ itemID: ItemID?) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: interactable.kind,
            position: interactable.position,
            title: interactable.title,
            lines: interactable.lines,
            rewardItem: itemID,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: interactable.grantsFlag
        )
    }

    func updateSelectedInteractableRewardMarks(_ amount: Int) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: interactable.kind,
            position: interactable.position,
            title: interactable.title,
            lines: interactable.lines,
            rewardItem: interactable.rewardItem,
            rewardMarks: amount > 0 ? amount : nil,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: interactable.grantsFlag
        )
    }

    func updateSelectedInteractableRequiredFlag(_ flag: QuestFlag?) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: interactable.kind,
            position: interactable.position,
            title: interactable.title,
            lines: interactable.lines,
            rewardItem: interactable.rewardItem,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: flag,
            grantsFlag: interactable.grantsFlag
        )
    }

    func updateSelectedInteractableGrantsFlag(_ flag: QuestFlag?) {
        guard let index = selectedInteractableIndex else { return }
        let interactable = document.maps[document.selectedMapIndex].interactables[index]
        document.maps[document.selectedMapIndex].interactables[index] = InteractableDefinition(
            id: interactable.id,
            kind: interactable.kind,
            position: interactable.position,
            title: interactable.title,
            lines: interactable.lines,
            rewardItem: interactable.rewardItem,
            rewardMarks: interactable.rewardMarks,
            requiredFlag: interactable.requiredFlag,
            grantsFlag: flag
        )
    }

    func updateSelectedPortalDestinationMap(_ mapID: String) {
        guard let index = selectedPortalIndex,
              let destinationMap = document.maps.first(where: { $0.id == mapID }) else {
            return
        }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: destinationMap.id,
            toPosition: destinationMap.spawn,
            requiredFlag: portal.requiredFlag,
            blockedMessage: portal.blockedMessage
        )
    }

    func syncSelectedPortalToDestinationSpawn() {
        guard let index = selectedPortalIndex else { return }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        guard let destinationMap = document.maps.first(where: { $0.id == portal.toMap }) else { return }
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: destinationMap.id,
            toPosition: destinationMap.spawn,
            requiredFlag: portal.requiredFlag,
            blockedMessage: portal.blockedMessage
        )
    }

    func updateSelectedPortalDestinationX(_ value: Int) {
        guard let index = selectedPortalIndex else { return }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: portal.toMap,
            toPosition: Position(x: max(0, value), y: portal.toPosition.y),
            requiredFlag: portal.requiredFlag,
            blockedMessage: portal.blockedMessage
        )
    }

    func updateSelectedPortalDestinationY(_ value: Int) {
        guard let index = selectedPortalIndex else { return }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: portal.toMap,
            toPosition: Position(x: portal.toPosition.x, y: max(0, value)),
            requiredFlag: portal.requiredFlag,
            blockedMessage: portal.blockedMessage
        )
    }

    func updateSelectedPortalRequiredFlag(_ flag: QuestFlag?) {
        guard let index = selectedPortalIndex else { return }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: portal.toMap,
            toPosition: portal.toPosition,
            requiredFlag: flag,
            blockedMessage: portal.blockedMessage
        )
    }

    func updateSelectedPortalBlockedMessage(_ value: String) {
        guard let index = selectedPortalIndex else { return }
        let portal = document.maps[document.selectedMapIndex].portals[index]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        document.maps[document.selectedMapIndex].portals[index] = Portal(
            from: portal.from,
            toMap: portal.toMap,
            toPosition: portal.toPosition,
            requiredFlag: portal.requiredFlag,
            blockedMessage: trimmed.isEmpty ? nil : trimmed
        )
    }

    func ensureShopForSelectedNPC() {
        guard let npc = selectedNPC else { return }
        if let existingIndex = document.shops.firstIndex(where: { $0.merchantID == npc.id }) {
            selectedShopIndex = existingIndex
            selectedShopOfferIndex = 0
            selectedContentTab = .shops
            statusLine = "OPENED \(document.shops[existingIndex].id.uppercased()) FOR \(npc.name.uppercased())."
            return
        }

        let newID = nextIdentifier(prefix: "\(npc.id)_shop", existing: document.shops.map(\.id))
        let shop = ShopDefinition(
            id: newID,
            merchantID: npc.id,
            merchantName: npc.name,
            introLine: "The merchant spreads a small cloth of goods.",
            offers: [
                ShopOffer(
                    id: "\(newID)_offer",
                    itemID: .healingTonic,
                    price: 2,
                    blurb: "A humble tonic for field work.",
                    repeatable: true
                )
            ]
        )
        document.shops.append(shop)
        selectedShopIndex = document.shops.count - 1
        selectedShopOfferIndex = 0
        selectedContentTab = .shops
        statusLine = "CREATED SHOP \(newID.uppercased()) FOR \(npc.name.uppercased())."
    }

    func focusNPC(id: String) {
        guard let npc = document.npcs.first(where: { $0.id == id }) else { return }
        if let mapIndex = document.maps.firstIndex(where: { $0.id == npc.mapID }) {
            document.selectedMapIndex = mapIndex
        }
        selectedCanvasSelection = EditorCanvasSelection(kind: .npc(id: id), position: npc.position)
        selectedContentTab = .npcs
        statusLine = "FOCUSED NPC \(npc.name.uppercased())."
    }

    func focusEnemy(id: String) {
        guard let enemy = document.enemies.first(where: { $0.id == id }) else { return }
        if let mapIndex = document.maps.firstIndex(where: { $0.id == enemy.mapID }) {
            document.selectedMapIndex = mapIndex
        }
        selectedCanvasSelection = EditorCanvasSelection(kind: .enemy(id: id), position: enemy.position)
        selectedContentTab = .enemies
        statusLine = "FOCUSED ENEMY \(enemy.name.uppercased())."
    }

    func selectDialogue(index: Int) {
        guard !document.dialogues.isEmpty else { return }
        selectedDialogueIndex = max(0, min(index, document.dialogues.count - 1))
    }

    func addDialogue() {
        let newID = nextIdentifier(prefix: "dialogue", existing: document.dialogues.map(\.id))
        document.dialogues.append(
            DialogueNode(
                id: newID,
                speaker: "New Speaker",
                lines: ["A fresh line waits to be written."]
            )
        )
        selectedDialogueIndex = document.dialogues.count - 1
        selectedContentTab = .dialogues
        statusLine = "ADDED DIALOGUE \(newID.uppercased())."
    }

    func removeSelectedDialogue() {
        guard !document.dialogues.isEmpty else { return }
        let removed = document.dialogues.remove(at: max(0, min(selectedDialogueIndex, document.dialogues.count - 1)))
        if document.dialogues.isEmpty {
            addDialogue()
        }
        selectedDialogueIndex = max(0, min(selectedDialogueIndex, max(0, document.dialogues.count - 1)))
        let replacementID = document.dialogues.first?.id ?? "dialogue_stub"
        for index in document.npcs.indices where document.npcs[index].dialogueID == removed.id {
            document.npcs[index].dialogueID = replacementID
        }
        statusLine = "REMOVED DIALOGUE \(removed.id.uppercased())."
    }

    func updateSelectedDialogueID(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let oldID = document.dialogues[index].id
        let newID = nextIdentifier(
            prefix: value,
            existing: document.dialogues.enumerated().compactMap { offset, node in
                offset == index ? nil : node.id
            }
        )
        let dialogue = document.dialogues[index]
        document.dialogues[index] = DialogueNode(id: newID, speaker: dialogue.speaker, lines: dialogue.lines)
        for npcIndex in document.npcs.indices where document.npcs[npcIndex].dialogueID == oldID {
            document.npcs[npcIndex].dialogueID = newID
        }
    }

    func updateSelectedDialogueSpeaker(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let dialogue = document.dialogues[index]
        document.dialogues[index] = DialogueNode(id: dialogue.id, speaker: value, lines: dialogue.lines)
    }

    func updateSelectedDialogueLinesText(_ value: String) {
        guard let index = selectedDialogueArrayIndex else { return }
        let dialogue = document.dialogues[index]
        let lines = normalizeLines(from: value)
        document.dialogues[index] = DialogueNode(id: dialogue.id, speaker: dialogue.speaker, lines: lines)
    }

    func selectQuestStage(index: Int) {
        guard !document.questFlow.stages.isEmpty else { return }
        selectedQuestStageIndex = max(0, min(index, document.questFlow.stages.count - 1))
    }

    func addQuestStage() {
        let usedFlags = Set(document.questFlow.stages.map(\.completeWhenFlag))
        let nextFlag = QuestFlag.allCases.first(where: { !usedFlags.contains($0) }) ?? .metElder
        let stages = document.questFlow.stages + [
            QuestStageDefinition(
                objective: "Define the next milestone.",
                completeWhenFlag: nextFlag
            )
        ]
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
        selectedQuestStageIndex = stages.count - 1
        selectedContentTab = .questFlow
        statusLine = "ADDED QUEST STAGE \(stages.count)."
    }

    func removeSelectedQuestStage() {
        guard document.questFlow.stages.count > 1 else {
            statusLine = "KEEP AT LEAST ONE QUEST STAGE."
            return
        }
        var stages = document.questFlow.stages
        stages.remove(at: max(0, min(selectedQuestStageIndex, stages.count - 1)))
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
        selectedQuestStageIndex = max(0, min(selectedQuestStageIndex, stages.count - 1))
    }

    func updateSelectedQuestObjective(_ value: String) {
        guard let index = selectedQuestStageArrayIndex else { return }
        var stages = document.questFlow.stages
        let stage = stages[index]
        stages[index] = QuestStageDefinition(
            objective: value,
            completeWhenFlag: stage.completeWhenFlag
        )
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
    }

    func updateSelectedQuestFlag(_ flag: QuestFlag) {
        guard let index = selectedQuestStageArrayIndex else { return }
        var stages = document.questFlow.stages
        let stage = stages[index]
        stages[index] = QuestStageDefinition(
            objective: stage.objective,
            completeWhenFlag: flag
        )
        document.questFlow = QuestFlowDefinition(stages: stages, completionText: document.questFlow.completionText)
    }

    func updateQuestCompletionText(_ value: String) {
        document.questFlow = QuestFlowDefinition(
            stages: document.questFlow.stages,
            completionText: value
        )
    }

    func selectEncounter(index: Int) {
        guard !document.encounters.isEmpty else { return }
        selectedEncounterIndex = max(0, min(index, document.encounters.count - 1))
    }

    func addEncounter() {
        let enemyID = document.enemies.first?.id ?? "enemy"
        let newID = nextIdentifier(prefix: "encounter", existing: document.encounters.map(\.id))
        document.encounters.append(
            EncounterDefinition(
                id: newID,
                enemyID: enemyID,
                introLine: "A fresh threat enters the path."
            )
        )
        selectedEncounterIndex = document.encounters.count - 1
        selectedContentTab = .encounters
        statusLine = "ADDED ENCOUNTER \(newID.uppercased())."
    }

    func removeSelectedEncounter() {
        guard !document.encounters.isEmpty else { return }
        document.encounters.remove(at: max(0, min(selectedEncounterIndex, document.encounters.count - 1)))
        if document.encounters.isEmpty {
            addEncounter()
        } else {
            selectedEncounterIndex = max(0, min(selectedEncounterIndex, document.encounters.count - 1))
        }
    }

    func updateSelectedEncounterID(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let newID = nextIdentifier(
            prefix: value,
            existing: document.encounters.enumerated().compactMap { offset, encounter in
                offset == index ? nil : encounter.id
            }
        )
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(id: newID, enemyID: encounter.enemyID, introLine: encounter.introLine)
    }

    func updateSelectedEncounterEnemyID(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(
            id: encounter.id,
            enemyID: sanitizeIdentifier(value),
            introLine: encounter.introLine
        )
    }

    func updateSelectedEncounterIntro(_ value: String) {
        guard let index = selectedEncounterArrayIndex else { return }
        let encounter = document.encounters[index]
        document.encounters[index] = EncounterDefinition(
            id: encounter.id,
            enemyID: encounter.enemyID,
            introLine: value
        )
    }

    func selectShop(index: Int) {
        guard !document.shops.isEmpty else { return }
        selectedShopIndex = max(0, min(index, document.shops.count - 1))
        selectedShopOfferIndex = 0
    }

    func addShop() {
        let merchant = document.npcs.first
        let merchantID = merchant?.id ?? "merchant"
        let merchantName = merchant?.name ?? "New Merchant"
        let newID = nextIdentifier(prefix: "shop", existing: document.shops.map(\.id))
        document.shops.append(
            ShopDefinition(
                id: newID,
                merchantID: merchantID,
                merchantName: merchantName,
                introLine: "A fresh ledger waits to be stocked.",
                offers: [
                    ShopOffer(
                        id: "\(newID)_offer",
                        itemID: .healingTonic,
                        price: 2,
                        blurb: "A dependable staple.",
                        repeatable: true
                    )
                ]
            )
        )
        selectedShopIndex = document.shops.count - 1
        selectedShopOfferIndex = 0
        selectedContentTab = .shops
        statusLine = "ADDED SHOP \(newID.uppercased())."
    }

    func removeSelectedShop() {
        guard !document.shops.isEmpty else { return }
        document.shops.remove(at: max(0, min(selectedShopIndex, document.shops.count - 1)))
        if document.shops.isEmpty {
            addShop()
        } else {
            selectedShopIndex = max(0, min(selectedShopIndex, document.shops.count - 1))
            selectedShopOfferIndex = 0
        }
    }

    func updateSelectedShopID(_ value: String) {
        guard let index = selectedShopArrayIndex else { return }
        let newID = nextIdentifier(
            prefix: value,
            existing: document.shops.enumerated().compactMap { offset, shop in
                offset == index ? nil : shop.id
            }
        )
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: newID,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: shop.offers.enumerated().map { offerIndex, offer in
                ShopOffer(
                    id: offerIndex == 0 ? "\(newID)_offer" : offer.id.replacingOccurrences(of: shop.id, with: newID),
                    itemID: offer.itemID,
                    price: offer.price,
                    blurb: offer.blurb,
                    repeatable: offer.repeatable
                )
            }
        )
    }

    func updateSelectedShopIntro(_ value: String) {
        guard let index = selectedShopArrayIndex else { return }
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: value,
            offers: shop.offers
        )
    }

    func updateSelectedShopMerchantID(_ merchantID: String) {
        guard let index = selectedShopArrayIndex else { return }
        let npc = document.npcs.first(where: { $0.id == merchantID })
        let shop = document.shops[index]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: merchantID,
            merchantName: npc?.name ?? shop.merchantName,
            introLine: shop.introLine,
            offers: shop.offers
        )
    }

    func addShopOffer() {
        guard let index = selectedShopArrayIndex else { return }
        let shop = document.shops[index]
        let offerID = nextIdentifier(prefix: "\(shop.id)_offer", existing: shop.offers.map(\.id))
        let offers = shop.offers + [
            ShopOffer(
                id: offerID,
                itemID: .healingTonic,
                price: 2,
                blurb: "A new item waits for a description.",
                repeatable: true
            )
        ]
        document.shops[index] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: offers
        )
        selectedShopOfferIndex = offers.count - 1
    }

    func removeSelectedShopOffer() {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        var offers = document.shops[shopIndex].offers
        guard offers.count > 1 else {
            statusLine = "KEEP AT LEAST ONE SHOP OFFER."
            return
        }
        offers.remove(at: offerIndex)
        let shop = document.shops[shopIndex]
        document.shops[shopIndex] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: offers
        )
        selectedShopOfferIndex = max(0, min(selectedShopOfferIndex, offers.count - 1))
    }

    func selectShopOffer(index: Int) {
        guard let shop = selectedShop, !shop.offers.isEmpty else { return }
        selectedShopOfferIndex = max(0, min(index, shop.offers.count - 1))
    }

    func updateSelectedShopOfferID(_ value: String) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        let shop = document.shops[shopIndex]
        let newID = nextIdentifier(
            prefix: value,
            existing: shop.offers.enumerated().compactMap { offset, offer in
                offset == offerIndex ? nil : offer.id
            }
        )
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: newID,
                itemID: offer.itemID,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferItemID(_ value: ItemID) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: value,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferPrice(_ value: Int) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: max(0, value),
                blurb: offer.blurb,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferBlurb(_ value: String) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: offer.price,
                blurb: value,
                repeatable: offer.repeatable
            )
        }
    }

    func updateSelectedShopOfferRepeatable(_ value: Bool) {
        guard let shopIndex = selectedShopArrayIndex,
              let offerIndex = selectedShopOfferArrayIndex else { return }
        replaceShopOffer(at: offerIndex, inShop: shopIndex) { offer in
            ShopOffer(
                id: offer.id,
                itemID: offer.itemID,
                price: offer.price,
                blurb: offer.blurb,
                repeatable: value
            )
        }
    }

    private func sanitizeIdentifier(_ value: String) -> String {
        let filtered = value
            .lowercased()
            .map { char -> Character in
                if char.isLetter || char.isNumber {
                    return char
                }
                return "_"
            }
        let collapsed = String(filtered)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "new_adventure" : collapsed
    }

    private func sanitizeFolderName(_ value: String) -> String {
        let safe = sanitizeIdentifier(value)
        return safe.isEmpty ? "new_adventure" : safe
    }

    private func resetSecondarySelections() {
        selectedDialogueIndex = 0
        selectedQuestStageIndex = 0
        selectedEncounterIndex = 0
        selectedShopIndex = 0
        selectedShopOfferIndex = 0
    }

    private var selectedNPCIndex: Int? {
        guard case .npc(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.npcs.firstIndex(where: { $0.id == id })
    }

    private var selectedEnemyIndex: Int? {
        guard case .enemy(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.enemies.firstIndex(where: { $0.id == id })
    }

    private var selectedInteractableIndex: Int? {
        guard case .interactable(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.maps[document.selectedMapIndex].interactables.firstIndex(where: { $0.id == id })
    }

    private var selectedPortalIndex: Int? {
        guard case .portal(let index) = selectedCanvasSelection?.kind else { return nil }
        guard index >= 0, index < document.maps[document.selectedMapIndex].portals.count else { return nil }
        return index
    }

    private var selectedDialogueArrayIndex: Int? {
        guard !document.dialogues.isEmpty else { return nil }
        return max(0, min(selectedDialogueIndex, document.dialogues.count - 1))
    }

    private var selectedQuestStageArrayIndex: Int? {
        guard !document.questFlow.stages.isEmpty else { return nil }
        return max(0, min(selectedQuestStageIndex, document.questFlow.stages.count - 1))
    }

    private var selectedEncounterArrayIndex: Int? {
        guard !document.encounters.isEmpty else { return nil }
        return max(0, min(selectedEncounterIndex, document.encounters.count - 1))
    }

    private var selectedShopArrayIndex: Int? {
        guard !document.shops.isEmpty else { return nil }
        return max(0, min(selectedShopIndex, document.shops.count - 1))
    }

    private var selectedShopOfferArrayIndex: Int? {
        guard let shop = selectedShop, !shop.offers.isEmpty else { return nil }
        return max(0, min(selectedShopOfferIndex, shop.offers.count - 1))
    }

    private func placeNPC(at position: Position) {
        guard let mapID = currentMapID else { return }
        if let existing = document.npcs.first(where: { $0.mapID == mapID && $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .npc(id: existing.id), position: position)
            statusLine = "NPC \(existing.name.uppercased()) IS ALREADY AT \(position.x),\(position.y)."
            return
        }

        let npcID = nextIdentifier(prefix: "npc", existing: document.npcs.map(\.id))
        let number = suffixNumber(from: npcID)
        let name = "Wanderer \(number)"
        let dialogueID = nextIdentifier(prefix: "\(npcID)_intro", existing: document.dialogues.map(\.id))
        let npc = NPCState(
            id: npcID,
            name: name,
            position: position,
            mapID: mapID,
            dialogueID: dialogueID,
            glyphSymbol: "&",
            glyphColor: .yellow,
            dialogueState: 0
        )
        document.npcs.append(npc)

        if !document.dialogues.contains(where: { $0.id == dialogueID }) {
            document.dialogues.append(
                DialogueNode(
                    id: dialogueID,
                    speaker: name,
                    lines: [
                        "The cartographer has only just started this road.",
                        "Return later and there will be more to say."
                    ]
                )
            )
        }

        selectedCanvasSelection = EditorCanvasSelection(kind: .npc(id: npcID), position: position)
        statusLine = "PLACED NPC \(name.uppercased()) AT \(position.x),\(position.y)."
    }

    private func placeEnemy(at position: Position) {
        guard let mapID = currentMapID else { return }
        if let existing = document.enemies.first(where: { $0.mapID == mapID && $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .enemy(id: existing.id), position: position)
            statusLine = "ENEMY \(existing.name.uppercased()) IS ALREADY AT \(position.x),\(position.y)."
            return
        }

        let enemyID = nextIdentifier(prefix: "enemy", existing: document.enemies.map(\.id))
        let number = suffixNumber(from: enemyID)
        let enemy = EnemyState(
            id: enemyID,
            name: "Shade \(number)",
            position: position,
            hp: 8,
            maxHP: 8,
            attack: 3,
            defense: 1,
            ai: .stalk,
            glyph: "g",
            color: .red,
            mapID: mapID,
            active: true
        )
        document.enemies.append(enemy)
        selectedCanvasSelection = EditorCanvasSelection(kind: .enemy(id: enemyID), position: position)
        statusLine = "PLACED ENEMY \(enemy.name.uppercased()) AT \(position.x),\(position.y)."
    }

    private func placeInteractable(at position: Position) {
        guard !document.maps.isEmpty else { return }
        if let existing = currentMap?.interactables.first(where: { $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .interactable(id: existing.id), position: position)
            statusLine = "INTERACTABLE \(existing.id.uppercased()) IS ALREADY AT \(position.x),\(position.y)."
            return
        }

        let interactableID = nextIdentifier(
            prefix: selectedInteractableKind.rawValue,
            existing: document.maps.flatMap { $0.interactables.map(\.id) }
        )
        let interactable = InteractableDefinition(
            id: interactableID,
            kind: selectedInteractableKind,
            position: position,
            title: selectedInteractableKind.editorTitle,
            lines: selectedInteractableKind.defaultLines,
            rewardItem: selectedInteractableKind == .chest ? .healingTonic : nil,
            rewardMarks: nil,
            requiredFlag: nil,
            grantsFlag: nil
        )
        document.maps[document.selectedMapIndex].interactables.append(interactable)
        selectedCanvasSelection = EditorCanvasSelection(kind: .interactable(id: interactableID), position: position)
        statusLine = "PLACED \(selectedInteractableKind.rawValue.uppercased()) AT \(position.x),\(position.y)."
    }

    private func placePortal(at position: Position) {
        guard !document.maps.isEmpty else { return }
        if let index = currentMap?.portals.firstIndex(where: { $0.from == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .portal(index: index), position: position)
            statusLine = "PORTAL IS ALREADY AT \(position.x),\(position.y)."
            return
        }

        let destinationIndex = document.maps.count > 1
            ? (document.selectedMapIndex + 1) % document.maps.count
            : document.selectedMapIndex
        let destinationMap = document.maps[destinationIndex]
        let portal = Portal(
            from: position,
            toMap: destinationMap.id,
            toPosition: destinationMap.spawn,
            requiredFlag: nil,
            blockedMessage: nil
        )
        document.maps[document.selectedMapIndex].portals.append(portal)
        let newIndex = document.maps[document.selectedMapIndex].portals.count - 1
        selectedCanvasSelection = EditorCanvasSelection(kind: .portal(index: newIndex), position: position)
        statusLine = "PLACED PORTAL TO \(destinationMap.name.uppercased()) FROM \(position.x),\(position.y)."
    }

    private func setSpawn(at position: Position) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].spawn = position
        selectedCanvasSelection = EditorCanvasSelection(kind: .spawn, position: position)
        statusLine = "SPAWN MOVED TO \(position.x),\(position.y)."
    }

    private func erase(at position: Position) {
        guard !document.maps.isEmpty else { return }
        let mapID = document.maps[document.selectedMapIndex].id

        if let index = document.npcs.firstIndex(where: { $0.mapID == mapID && $0.position == position }) {
            let removed = document.npcs.remove(at: index)
            selectedCanvasSelection = nil
            statusLine = "REMOVED NPC \(removed.name.uppercased())."
            return
        }

        if let index = document.enemies.firstIndex(where: { $0.mapID == mapID && $0.position == position }) {
            let removed = document.enemies.remove(at: index)
            selectedCanvasSelection = nil
            statusLine = "REMOVED ENEMY \(removed.name.uppercased())."
            return
        }

        if let index = document.maps[document.selectedMapIndex].interactables.firstIndex(where: { $0.position == position }) {
            let removed = document.maps[document.selectedMapIndex].interactables.remove(at: index)
            selectedCanvasSelection = nil
            statusLine = "REMOVED INTERACTABLE \(removed.id.uppercased())."
            return
        }

        if let index = document.maps[document.selectedMapIndex].portals.firstIndex(where: { $0.from == position }) {
            document.maps[document.selectedMapIndex].portals.remove(at: index)
            selectedCanvasSelection = nil
            statusLine = "REMOVED PORTAL AT \(position.x),\(position.y)."
            return
        }

        if document.maps[document.selectedMapIndex].spawn == position {
            document.maps[document.selectedMapIndex].spawn = Position(x: 1, y: 1)
            selectedCanvasSelection = EditorCanvasSelection(kind: .spawn, position: Position(x: 1, y: 1))
            statusLine = "SPAWN RESET TO 1,1."
            return
        }

        document.maps[document.selectedMapIndex].setGlyph(".", atX: position.x, y: position.y)
        selectedCanvasSelection = EditorCanvasSelection(kind: .tile, position: position)
        statusLine = "CLEARED TILE AT \(position.x),\(position.y)."
    }

    private func selectCanvasObject(at position: Position) {
        guard let map = currentMap else { return }
        if let npc = document.npcs.first(where: { $0.mapID == map.id && $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .npc(id: npc.id), position: position)
            statusLine = "SELECTED NPC \(npc.name.uppercased())."
            return
        }

        if let enemy = document.enemies.first(where: { $0.mapID == map.id && $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .enemy(id: enemy.id), position: position)
            statusLine = "SELECTED ENEMY \(enemy.name.uppercased())."
            return
        }

        if let interactable = map.interactables.first(where: { $0.position == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .interactable(id: interactable.id), position: position)
            statusLine = "SELECTED INTERACTABLE \(interactable.id.uppercased())."
            return
        }

        if let index = map.portals.firstIndex(where: { $0.from == position }) {
            selectedCanvasSelection = EditorCanvasSelection(kind: .portal(index: index), position: position)
            statusLine = "SELECTED PORTAL AT \(position.x),\(position.y)."
            return
        }

        if map.spawn == position {
            selectedCanvasSelection = EditorCanvasSelection(kind: .spawn, position: position)
            statusLine = "SELECTED MAP SPAWN."
            return
        }

        selectedCanvasSelection = EditorCanvasSelection(kind: .tile, position: position)
        statusLine = "SELECTED TILE AT \(position.x),\(position.y)."
    }

    private func nextIdentifier(prefix: String, existing: [String]) -> String {
        let base = sanitizeIdentifier(prefix)
        let existingSet = Set(existing)
        if !existingSet.contains(base) {
            return base
        }

        var counter = 1
        while existingSet.contains("\(base)_\(counter)") {
            counter += 1
        }
        return "\(base)_\(counter)"
    }

    private func suffixNumber(from identifier: String) -> Int {
        let component = identifier.split(separator: "_").last.flatMap { Int($0) }
        return component ?? (document.npcs.count + document.enemies.count + 1)
    }

    private func replaceShopOffer(at offerIndex: Int, inShop shopIndex: Int, transform: (ShopOffer) -> ShopOffer) {
        let shop = document.shops[shopIndex]
        var offers = shop.offers
        offers[offerIndex] = transform(offers[offerIndex])
        document.shops[shopIndex] = ShopDefinition(
            id: shop.id,
            merchantID: shop.merchantID,
            merchantName: shop.merchantName,
            introLine: shop.introLine,
            offers: offers
        )
    }

    private func normalizeLines(from value: String) -> [String] {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["..."] : lines
    }

    private static func defaultPlaytestLauncher(adventureID: AdventureID) throws {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--graphics", "--playtest", adventureID.rawValue]
        try process.run()
    }

    private func glyphAt(_ position: Position, in map: EditableMap) -> Character {
        guard position.y >= 0, position.y < map.lines.count else { return "." }
        let row = Array(map.lines[position.y])
        guard position.x >= 0, position.x < row.count else { return "." }
        return row[position.x]
    }

    private func displayGlyph(_ glyph: Character) -> String {
        glyph == " " ? "EMP" : String(glyph)
    }

    private func tileTypeLabel(_ type: TileType) -> String {
        switch type {
        case .floor: return "FLOOR"
        case .wall: return "WALL"
        case .water: return "WATER"
        case .brush: return "BRUSH"
        case .doorLocked: return "LOCKED DOOR"
        case .doorOpen: return "OPEN DOOR"
        case .shrine: return "SHRINE"
        case .stairs: return "STAIRS"
        case .beacon: return "BEACON"
        }
    }

    private func interactableGlyph(for kind: InteractableKind) -> String {
        switch kind {
        case .npc: return "&"
        case .shrine: return "*"
        case .chest: return "$"
        case .bed: return "Z"
        case .gate: return "+"
        case .beacon: return "B"
        case .plate: return "o"
        case .switchRune: return "="
        }
    }

    private func color(for ansi: ANSIColor) -> Color {
        switch ansi {
        case .black: return .black
        case .red: return Color(red: 0.86, green: 0.22, blue: 0.16)
        case .green: return Color(red: 0.27, green: 0.78, blue: 0.19)
        case .yellow: return Color(red: 0.98, green: 0.84, blue: 0.20)
        case .blue: return Color(red: 0.24, green: 0.56, blue: 0.92)
        case .magenta: return Color(red: 0.76, green: 0.34, blue: 0.86)
        case .cyan: return Color(red: 0.22, green: 0.80, blue: 0.86)
        case .white: return Color(red: 0.95, green: 0.94, blue: 0.87)
        case .brightBlack: return Color(red: 0.42, green: 0.42, blue: 0.44)
        case .reset: return Color(red: 0.95, green: 0.94, blue: 0.87)
        }
    }

    private func color(for kind: InteractableKind) -> Color {
        switch kind {
        case .npc:
            return Color(red: 0.98, green: 0.84, blue: 0.20)
        case .shrine:
            return Color(red: 0.78, green: 0.42, blue: 0.94)
        case .chest:
            return Color(red: 0.84, green: 0.56, blue: 0.12)
        case .bed:
            return Color(red: 0.65, green: 0.32, blue: 0.18)
        case .gate:
            return Color(red: 0.88, green: 0.72, blue: 0.18)
        case .beacon:
            return Color(red: 0.99, green: 0.94, blue: 0.34)
        case .plate:
            return Color(red: 0.72, green: 0.72, blue: 0.72)
        case .switchRune:
            return Color(red: 0.28, green: 0.74, blue: 0.90)
        }
    }

    private static func makeDocument(entry: AdventureCatalogEntry, content: GameContent) -> EditableAdventureDocument {
        let maps = content.maps.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                EditableMap(
                    id: $0.id,
                    name: $0.name,
                    lines: $0.lines,
                    spawn: $0.spawn,
                    portals: $0.portals,
                    interactables: $0.interactables
                )
            }

        let folderName = sourceFolderName(for: entry)
        return EditableAdventureDocument(
            folderName: folderName,
            adventureID: entry.id.rawValue,
            title: content.title,
            summary: content.summary,
            introLine: content.introLine,
            maps: maps,
            selectedMapIndex: 0,
            questFlow: content.questFlow,
            dialogues: content.dialogues.values.sorted { $0.id < $1.id },
            encounters: content.encounters.values.sorted { $0.id < $1.id },
            npcs: content.initialNPCs,
            enemies: content.initialEnemies,
            shops: content.shops.values.sorted { $0.id < $1.id }
        )
    }

    private static func makeBlankDocument() -> EditableAdventureDocument {
        let starterDialogue = DialogueNode(
            id: "guide_intro",
            speaker: "Guide",
            lines: [
                "This pack is yours to reshape.",
                "Paint the land, move the people, and write a better fate."
            ]
        )
        let starterNPC = NPCState(
            id: "guide_keeper",
            name: "Guide Keeper",
            position: Position(x: 3, y: 2),
            mapID: "merrow_village",
            dialogueID: starterDialogue.id,
            glyphSymbol: "&",
            glyphColor: .yellow,
            dialogueState: 0
        )
        let starterEnemy = EnemyState(
            id: "field_shade",
            name: "Field Shade",
            position: Position(x: 12, y: 6),
            hp: 8,
            maxHP: 8,
            attack: 3,
            defense: 1,
            ai: .stalk,
            glyph: "g",
            color: .red,
            mapID: "merrow_village",
            active: true
        )
        let starterShop = ShopDefinition(
            id: "guide_goods",
            merchantID: starterNPC.id,
            merchantName: starterNPC.name,
            introLine: "A simple bench of wares proves the shop system is alive.",
            offers: [
                ShopOffer(
                    id: "guide_goods_tonic",
                    itemID: .healingTonic,
                    price: 2,
                    blurb: "A starter tonic for quick testing.",
                    repeatable: true
                )
            ]
        )
        return EditableAdventureDocument(
            folderName: "new_adventure",
            adventureID: "new_adventure",
            title: "New Adventure",
            summary: "A custom road beyond the bundled campaigns.",
            introLine: "A fresh path opens beyond the embers.",
            maps: [
                EditableMap(
                    id: "merrow_village",
                    name: "Starter Grounds",
                    lines: makeStarterMapLines(),
                    spawn: Position(x: 2, y: 2),
                    portals: [],
                    interactables: [
                        InteractableDefinition(
                            id: "starter_chest",
                            kind: .chest,
                            position: Position(x: 6, y: 4),
                            title: "Starter Cache",
                            lines: ["A small cache sits here for testing rewards."],
                            rewardItem: .healingTonic,
                            rewardMarks: 4,
                            requiredFlag: nil,
                            grantsFlag: nil
                        )
                    ]
                )
            ],
            selectedMapIndex: 0,
            questFlow: QuestFlowDefinition(
                stages: [
                    QuestStageDefinition(
                        objective: "Find the first landmark.",
                        completeWhenFlag: .metElder
                    )
                ],
                completionText: "The first chapter closes."
            ),
            dialogues: [starterDialogue],
            encounters: [
                EncounterDefinition(
                    id: "starter_skirmish",
                    enemyID: starterEnemy.id,
                    introLine: "A starter skirmish proves the encounter table is wired."
                )
            ],
            npcs: [starterNPC],
            enemies: [starterEnemy],
            shops: [starterShop]
        )
    }

    private static func makeStarterMapLines() -> [String] {
        [
            "####################",
            "#..................#",
            "#..................#",
            "#....\"\"\"...........#",
            "#..................#",
            "#...........~~~~...#",
            "#..................#",
            "#..............*...#",
            "#..................#",
            "####################"
        ]
    }

    private static func sourceFolderName(for entry: AdventureCatalogEntry) -> String {
        let value = entry.folder
        if value.contains("/") {
            return URL(fileURLWithPath: value).lastPathComponent
        }
        return value
            .split(separator: "/")
            .last
            .map(String.init) ?? entry.id.rawValue
    }
}
