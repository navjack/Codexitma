import AppKit
import Foundation
import SwiftUI

@MainActor
enum AdventureEditorLauncher {
    private static var retainedDelegate: AdventureEditorAppDelegate?

    static func run(library: GameContentLibrary) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AdventureEditorAppDelegate(library: library)
        retainedDelegate = delegate
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

@MainActor
final class AdventureEditorAppDelegate: NSObject, NSApplicationDelegate {
    private let store: AdventureEditorStore
    private var window: NSWindow?

    init(library: GameContentLibrary) {
        self.store = AdventureEditorStore(library: library)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma Adventure Editor"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 1180, height: 760)
        window.center()
        window.contentView = NSHostingView(rootView: AdventureEditorRootView(store: store))
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case terrain
    case npc
    case enemy
    case interactable
    case portal
    case spawn
    case erase
    case select

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .terrain: return "TERR"
        case .npc: return "NPC"
        case .enemy: return "ENM"
        case .interactable: return "INT"
        case .portal: return "PORT"
        case .spawn: return "SPAWN"
        case .erase: return "ERASE"
        case .select: return "SEL"
        }
    }

    var title: String {
        switch self {
        case .terrain: return "Terrain"
        case .npc: return "NPC"
        case .enemy: return "Enemy"
        case .interactable: return "Interactable"
        case .portal: return "Portal"
        case .spawn: return "Spawn"
        case .erase: return "Erase"
        case .select: return "Select"
        }
    }

    var helpText: String {
        switch self {
        case .terrain:
            return "Paint terrain onto the tile layer."
        case .npc:
            return "Place layered NPC records and auto-seed a stub dialogue."
        case .enemy:
            return "Place layered enemies on top of the terrain."
        case .interactable:
            return "Place a coordinate-based interactable record."
        case .portal:
            return "Place a portal that links to the next map's spawn."
        case .spawn:
            return "Move the active map's player spawn point."
        case .erase:
            return "Remove a placed object, or clear a tile back to floor."
        case .select:
            return "Inspect what already exists at a coordinate."
        }
    }
}

enum EditorContentTab: String, CaseIterable, Identifiable {
    case maps
    case dialogues
    case questFlow
    case encounters
    case shops
    case npcs
    case enemies

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .maps: return "MAPS"
        case .dialogues: return "DIALOG"
        case .questFlow: return "QUEST"
        case .encounters: return "ENCOUN"
        case .shops: return "SHOPS"
        case .npcs: return "NPCS"
        case .enemies: return "ENEMIES"
        }
    }

    var title: String {
        switch self {
        case .maps: return "Maps"
        case .dialogues: return "Dialogues"
        case .questFlow: return "Quest Flow"
        case .encounters: return "Encounters"
        case .shops: return "Shops"
        case .npcs: return "NPC Roster"
        case .enemies: return "Enemy Roster"
        }
    }
}

enum EditorSelectionKind: Equatable {
    case tile
    case spawn
    case npc(id: String)
    case enemy(id: String)
    case interactable(id: String)
    case portal(index: Int)
}

struct EditorCanvasSelection: Equatable {
    let kind: EditorSelectionKind
    let position: Position
}

fileprivate struct EditorCanvasOverlay {
    let glyph: String
    let fill: Color
    let text: Color
}

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
        statusLine = "LOADED \(entry.title.uppercased()) FOR EDITING."
    }

    func createBlankAdventure() {
        selectedCatalogID = nil
        document = Self.makeBlankDocument()
        resetSecondarySelections()
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        statusLine = "BLANK TEMPLATE CREATED. SAVE IT TO EXPORT A NEW ADVENTURE PACK."
    }

    func saveCurrentPack() {
        do {
            let exportedURL = try exporter.save(document: document)
            statusLine = "EXPORTED TO \(exportedURL.path.uppercased())"
        } catch {
            statusLine = "EXPORT FAILED: \(String(describing: error).uppercased())"
        }
    }

    func saveAndPlaytestCurrentPack() {
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

    fileprivate func overlay(atX x: Int, y: Int) -> EditorCanvasOverlay? {
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

struct EditableAdventureDocument {
    var folderName: String
    var adventureID: String
    var title: String
    var summary: String
    var introLine: String
    var maps: [EditableMap]
    var selectedMapIndex: Int
    var questFlow: QuestFlowDefinition
    var dialogues: [DialogueNode]
    var encounters: [EncounterDefinition]
    var npcs: [NPCState]
    var enemies: [EnemyState]
    var shops: [ShopDefinition]
}

struct EditableMap: Identifiable {
    var id: String
    var name: String
    var lines: [String]
    var spawn: Position
    var portals: [Portal]
    var interactables: [InteractableDefinition]

    mutating func setGlyph(_ glyph: Character, atX x: Int, y: Int) {
        guard y >= 0, y < lines.count else { return }
        var row = Array(lines[y])
        guard x >= 0, x < row.count else { return }
        row[x] = glyph
        lines[y] = String(row)
    }
}

struct AdventurePackExporter {
    private let fileManager: FileManager
    private let externalRootURL: URL

    init(fileManager: FileManager = .default, externalRootURL: URL? = nil) {
        self.fileManager = fileManager
        if let externalRootURL {
            self.externalRootURL = externalRootURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.externalRootURL = appSupport
                .appendingPathComponent("Codexitma", isDirectory: true)
                .appendingPathComponent("Adventures", isDirectory: true)
        }
    }

    func save(document: EditableAdventureDocument) throws -> URL {
        let folderName = sanitizePathComponent(document.folderName.isEmpty ? document.adventureID : document.folderName)
        let packURL = externalRootURL.appendingPathComponent(folderName, isDirectory: true)
        let mapsURL = packURL.appendingPathComponent("maps", isDirectory: true)

        try fileManager.createDirectory(at: mapsURL, withIntermediateDirectories: true)

        let manifest = EditorAdventureManifest(
            id: AdventureID(rawValue: document.adventureID),
            title: document.title,
            summary: document.summary,
            introLine: document.introLine,
            objectivesFile: "quest_flow.json",
            worldFile: "world.json",
            dialoguesFile: "dialogues.json",
            encountersFile: "encounters.json",
            npcsFile: "npcs.json",
            enemiesFile: "enemies.json",
            shopsFile: "shops.json"
        )

        let maps = document.maps.map { map in
            MapDefinition(
                id: map.id,
                name: map.name,
                layoutFile: "maps/\(sanitizePathComponent(map.id)).txt",
                lines: map.lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
        }

        for map in maps {
            let layoutURL = packURL.appendingPathComponent(map.layoutFile)
            let text = map.lines.joined(separator: "\n") + "\n"
            try text.write(to: layoutURL, atomically: true, encoding: .utf8)
        }

        try writeJSON(manifest, to: packURL.appendingPathComponent("adventure.json"))
        try writeJSON(document.questFlow, to: packURL.appendingPathComponent("quest_flow.json"))
        try writeJSON(maps, to: packURL.appendingPathComponent("world.json"))
        try writeJSON(document.dialogues, to: packURL.appendingPathComponent("dialogues.json"))
        try writeJSON(document.encounters, to: packURL.appendingPathComponent("encounters.json"))
        try writeJSON(document.npcs, to: packURL.appendingPathComponent("npcs.json"))
        try writeJSON(document.enemies, to: packURL.appendingPathComponent("enemies.json"))
        try writeJSON(document.shops, to: packURL.appendingPathComponent("shops.json"))

        return packURL
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let filtered = value
            .lowercased()
            .map { char -> Character in
                if char.isLetter || char.isNumber || char == "_" || char == "-" {
                    return char
                }
                return "_"
            }
        let safe = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return safe.isEmpty ? "adventure" : safe
    }
}

private struct EditorAdventureManifest: Codable {
    let id: AdventureID
    let title: String
    let summary: String
    let introLine: String
    let objectivesFile: String
    let worldFile: String
    let dialoguesFile: String
    let encountersFile: String
    let npcsFile: String
    let enemiesFile: String
    let shopsFile: String
}

struct AdventureEditorRootView: View {
    @ObservedObject var store: AdventureEditorStore

    private let palette = AdventureEditorPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 12) {
                header

                HStack(alignment: .top, spacing: 12) {
                    sourcePanel
                        .frame(width: 240)

                    VStack(spacing: 12) {
                        metadataPanel
                        contentTabBar
                        contentPanel
                    }
                }

                footer
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack {
            Text("CODEXITMA ADVENTURE EDITOR")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.title)
            Spacer()
            Button("SAVE + PLAYTEST") {
                store.saveAndPlaytestCurrentPack()
            }
            .buttonStyle(EditorButtonStyle(background: palette.title))
            Button("SAVE PACK") {
                store.saveCurrentPack()
            }
            .buttonStyle(EditorButtonStyle(background: palette.action))
        }
    }

    private var sourcePanel: some View {
        EditorPanel(title: "SOURCES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT A BUNDLED OR EXTERNAL ADVENTURE, THEN FORK IT INTO THE EDITOR.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.catalog, id: \.id) { entry in
                            Button {
                                store.selectCatalogAdventure(entry.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(entry.id.rawValue)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedCatalogID == entry.id ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)

                Button("NEW BLANK TEMPLATE") {
                    store.createBlankAdventure()
                }
                .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
            }
        }
    }

    private var metadataPanel: some View {
        EditorPanel(title: "PACK METADATA", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    labeledField("FOLDER", text: Binding(
                        get: { store.document.folderName },
                        set: { store.updateFolderName($0) }
                    ))
                    labeledField("ADVENTURE ID", text: Binding(
                        get: { store.document.adventureID },
                        set: { store.updateAdventureID($0) }
                    ))
                }

                labeledField("TITLE", text: Binding(
                    get: { store.document.title },
                    set: { store.updateTitle($0) }
                ))

                labeledField("INTRO", text: Binding(
                    get: { store.document.introLine },
                    set: { store.updateIntroLine($0) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("SUMMARY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.document.summary },
                        set: { store.updateSummary($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(height: 72)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }

                Text("KEEP THE SAME ADVENTURE ID TO OVERRIDE A BUILT-IN PACK. CHANGE IT TO PUBLISH A NEW ADVENTURE.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mapListPanel: some View {
        EditorPanel(title: "MAPS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.maps.enumerated()), id: \.element.id) { index, map in
                            Button {
                                store.selectMap(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(map.name.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(map.id)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.document.selectedMapIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)

                HStack(spacing: 8) {
                    Button("ADD MAP") {
                        store.addMap()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DUP MAP") {
                        store.duplicateSelectedMap()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    private var contentTabBar: some View {
        EditorPanel(title: "EDITOR DATA", palette: palette) {
            HStack(spacing: 6) {
                ForEach(EditorContentTab.allCases) { tab in
                    Button {
                        store.selectContentTab(tab)
                    } label: {
                        Text(tab.shortLabel)
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(
                        EditorButtonStyle(
                            background: store.selectedContentTab == tab ? palette.title : palette.panelAlt
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var contentPanel: some View {
        switch store.selectedContentTab {
        case .maps:
            HStack(alignment: .top, spacing: 12) {
                mapListPanel
                    .frame(width: 240)
                mapEditorPanel
            }
        case .dialogues:
            dialoguesPanel
        case .questFlow:
            questFlowPanel
        case .encounters:
            encountersPanel
        case .shops:
            shopsPanel
        case .npcs:
            npcRosterPanel
        case .enemies:
            enemyRosterPanel
        }
    }

    private var mapEditorPanel: some View {
        EditorPanel(title: "MAP WORKBENCH", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                if store.currentMap != nil {
                    HStack(spacing: 8) {
                        labeledField("MAP ID", text: Binding(
                            get: { store.currentMap?.id ?? "" },
                            set: { store.updateCurrentMapID($0) }
                        ))
                        labeledField("MAP NAME", text: Binding(
                            get: { store.currentMap?.name ?? "" },
                            set: { store.updateCurrentMapName($0) }
                        ))
                    }

                    toolPalette

                    if store.selectedTool == .terrain {
                        tilePalette
                    }

                    if store.selectedTool == .interactable {
                        interactablePalette
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.currentMapCountsLine)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.text.opacity(0.84))

                            Text(store.selectedToolSummary)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text.opacity(0.80))
                                .fixedSize(horizontal: false, vertical: true)

                            ScrollView([.horizontal, .vertical]) {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(Array((store.currentMap?.lines ?? []).enumerated()), id: \.offset) { y, line in
                                        HStack(spacing: 1) {
                                            ForEach(Array(line.enumerated()), id: \.offset) { x, glyph in
                                                Button {
                                                    store.handleCanvasClick(x: x, y: y)
                                                } label: {
                                                    let overlay = store.overlay(atX: x, y: y)
                                                    ZStack {
                                                        Rectangle()
                                                            .fill(tileColor(for: glyph))

                                                        if store.isSpawn(x: x, y: y) {
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .stroke(palette.light.opacity(0.85), lineWidth: 1.2)
                                                                .padding(2)
                                                        }

                                                        if let overlay {
                                                            RoundedRectangle(cornerRadius: 2)
                                                                .fill(overlay.fill)
                                                                .padding(2)
                                                            Text(overlay.glyph)
                                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                                .foregroundStyle(overlay.text)
                                                        } else {
                                                            Text(displayGlyph(glyph))
                                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                                .foregroundStyle(palette.background)
                                                        }
                                                    }
                                                    .frame(width: 18, height: 18)
                                                    .overlay(
                                                        Rectangle().stroke(
                                                            store.isSelected(x: x, y: y) ? palette.title : palette.border.opacity(0.55),
                                                            lineWidth: store.isSelected(x: x, y: y) ? 1.5 : 0.5
                                                        )
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                                .padding(6)
                                .background(palette.panelAlt)
                            }
                            .frame(minHeight: 360)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }

                        selectionPanel
                            .frame(width: 220)
                    }
                } else {
                    Text("NO MAP IS ACTIVE.")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.text)
                }
            }
        }
    }

    private var toolPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EDITOR TOOLS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        store.selectTool(tool)
                    } label: {
                        Text(tool.shortLabel)
                            .frame(minWidth: 44)
                    }
                    .buttonStyle(
                        EditorButtonStyle(
                            background: store.selectedTool == tool ? palette.title : palette.panelAlt
                        )
                    )
                }
            }
        }
    }

    private var tilePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TILE PALETTE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                ForEach(editorTilePalette, id: \.glyph) { tile in
                    Button {
                        store.selectedGlyph = tile.glyph
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Rectangle()
                                    .fill(tileColor(for: tile.glyph))
                                Text(displayGlyph(tile.glyph))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.background)
                            }
                            .frame(width: 26, height: 26)
                            .overlay(
                                Rectangle().stroke(
                                    store.selectedGlyph == tile.glyph ? palette.title : palette.border,
                                    lineWidth: store.selectedGlyph == tile.glyph ? 2 : 1
                                )
                            )
                            Text(tile.label)
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text.opacity(0.82))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var interactablePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTERACTABLE KIND")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                ForEach(editorInteractablePalette, id: \.kind) { choice in
                    Button {
                        store.selectedInteractableKind = choice.kind
                    } label: {
                        VStack(spacing: 2) {
                            ZStack {
                                Rectangle()
                                    .fill(choice.color)
                                Text(choice.glyph)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.black)
                            }
                            .frame(width: 26, height: 26)
                            .overlay(
                                Rectangle().stroke(
                                    store.selectedInteractableKind == choice.kind ? palette.title : palette.border,
                                    lineWidth: store.selectedInteractableKind == choice.kind ? 2 : 1
                                )
                            )
                            Text(choice.label)
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text.opacity(0.82))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectionPanel: some View {
        EditorPanel(title: "SELECTION", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(store.selectionSummaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(palette.border)

                inspectorFields

                Divider()
                    .overlay(palette.border)

                Text("ACTIVE TOOL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Text(store.selectedTool.title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.title)

                Text(store.selectedTool.helpText.uppercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dialoguesPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "DIALOGUES", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(store.document.dialogues.enumerated()), id: \.element.id) { index, dialogue in
                                Button {
                                    store.selectDialogue(index: index)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(dialogue.id.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Text(dialogue.speaker)
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .opacity(0.78)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(store.selectedDialogueIndex == index ? palette.selection : palette.panelAlt)
                                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 360)

                    HStack(spacing: 8) {
                        Button("ADD") {
                            store.addDialogue()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP") {
                            store.removeSelectedDialogue()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            }
            .frame(width: 260)

            EditorPanel(title: "DIALOGUE EDITOR", palette: palette) {
                if let dialogue = store.selectedDialogue {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledField("DIALOGUE ID", text: Binding(
                            get: { store.selectedDialogue?.id ?? dialogue.id },
                            set: { store.updateSelectedDialogueID($0) }
                        ))

                        labeledField("SPEAKER", text: Binding(
                            get: { store.selectedDialogue?.speaker ?? dialogue.speaker },
                            set: { store.updateSelectedDialogueSpeaker($0) }
                        ))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("LINES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.label)
                            TextEditor(text: Binding(
                                get: { (store.selectedDialogue?.lines ?? dialogue.lines).joined(separator: "\n") },
                                set: { store.updateSelectedDialogueLinesText($0) }
                            ))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(palette.text)
                            .frame(minHeight: 220)
                            .padding(6)
                            .background(palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                    }
                } else {
                    emptyEditorLabel("NO DIALOGUE IS AVAILABLE.")
                }
            }
        }
    }

    private var questFlowPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "QUEST STAGES", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(store.document.questFlow.stages.enumerated()), id: \.offset) { index, stage in
                                Button {
                                    store.selectQuestStage(index: index)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("STAGE \(index + 1)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Text(stage.objective)
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .lineLimit(2)
                                            .opacity(0.78)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(store.selectedQuestStageIndex == index ? palette.selection : palette.panelAlt)
                                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 360)

                    HStack(spacing: 8) {
                        Button("ADD") {
                            store.addQuestStage()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP") {
                            store.removeSelectedQuestStage()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            }
            .frame(width: 260)

            EditorPanel(title: "QUEST FLOW", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    if let stage = store.selectedQuestStage {
                        labeledField("OBJECTIVE", text: Binding(
                            get: { store.selectedQuestStage?.objective ?? stage.objective },
                            set: { store.updateSelectedQuestObjective($0) }
                        ))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMPLETE WHEN FLAG")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.label)

                            Picker("Quest Flag", selection: Binding(
                                get: { store.selectedQuestStage?.completeWhenFlag ?? stage.completeWhenFlag },
                                set: { store.updateSelectedQuestFlag($0) }
                            )) {
                                ForEach(QuestFlag.allCases, id: \.self) { flag in
                                    Text(flag.rawValue).tag(flag)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMPLETION TEXT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { store.document.questFlow.completionText },
                            set: { store.updateQuestCompletionText($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(minHeight: 180)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var encountersPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "ENCOUNTERS", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(store.document.encounters.enumerated()), id: \.element.id) { index, encounter in
                                Button {
                                    store.selectEncounter(index: index)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(encounter.id.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Text(encounter.enemyID)
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .opacity(0.78)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(store.selectedEncounterIndex == index ? palette.selection : palette.panelAlt)
                                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 360)

                    HStack(spacing: 8) {
                        Button("ADD") {
                            store.addEncounter()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP") {
                            store.removeSelectedEncounter()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            }
            .frame(width: 260)

            EditorPanel(title: "ENCOUNTER EDITOR", palette: palette) {
                if let encounter = store.selectedEncounter {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledField("ENCOUNTER ID", text: Binding(
                            get: { store.selectedEncounter?.id ?? encounter.id },
                            set: { store.updateSelectedEncounterID($0) }
                        ))

                        labeledField("ENEMY ID", text: Binding(
                            get: { store.selectedEncounter?.enemyID ?? encounter.enemyID },
                            set: { store.updateSelectedEncounterEnemyID($0) }
                        ))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("INTRO LINE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.label)
                            TextEditor(text: Binding(
                                get: { store.selectedEncounter?.introLine ?? encounter.introLine },
                                set: { store.updateSelectedEncounterIntro($0) }
                            ))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(palette.text)
                            .frame(minHeight: 180)
                            .padding(6)
                            .background(palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                    }
                } else {
                    emptyEditorLabel("NO ENCOUNTER IS AVAILABLE.")
                }
            }
        }
    }

    private var shopsPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "SHOPS", palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(store.document.shops.enumerated()), id: \.element.id) { index, shop in
                                Button {
                                    store.selectShop(index: index)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shop.id.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        Text(shop.merchantName)
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .opacity(0.78)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(store.selectedShopIndex == index ? palette.selection : palette.panelAlt)
                                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    HStack(spacing: 8) {
                        Button("ADD") {
                            store.addShop()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP") {
                            store.removeSelectedShop()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            }
            .frame(width: 260)

            EditorPanel(title: "SHOP EDITOR", palette: palette) {
                if let shop = store.selectedShop {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledField("SHOP ID", text: Binding(
                            get: { store.selectedShop?.id ?? shop.id },
                            set: { store.updateSelectedShopID($0) }
                        ))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("MERCHANT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.label)
                            Picker("Merchant", selection: Binding(
                                get: { store.selectedShop?.merchantID ?? shop.merchantID },
                                set: { store.updateSelectedShopMerchantID($0) }
                            )) {
                                ForEach(store.document.npcs, id: \.id) { npc in
                                    Text(npc.name.uppercased()).tag(npc.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("INTRO LINE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.label)
                            TextEditor(text: Binding(
                                get: { store.selectedShop?.introLine ?? shop.introLine },
                                set: { store.updateSelectedShopIntro($0) }
                            ))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(palette.text)
                            .frame(height: 78)
                            .padding(6)
                            .background(palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }

                        Text("OFFERS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)

                        HStack(alignment: .top, spacing: 8) {
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(Array((store.selectedShop?.offers ?? []).enumerated()), id: \.element.id) { index, offer in
                                        Button {
                                            store.selectShopOffer(index: index)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(offer.id.uppercased())
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                Text("\(offer.itemID.rawValue)  \(offer.price)M")
                                                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                                                    .opacity(0.78)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(6)
                                            .background(store.selectedShopOfferIndex == index ? palette.selection : palette.panelAlt)
                                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(width: 220)
                            .frame(maxHeight: 220)

                            VStack(alignment: .leading, spacing: 8) {
                                if let offer = store.selectedShopOffer {
                                    labeledField("OFFER ID", text: Binding(
                                        get: { store.selectedShopOffer?.id ?? offer.id },
                                        set: { store.updateSelectedShopOfferID($0) }
                                    ))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ITEM")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(palette.label)
                                        Picker("Item", selection: Binding(
                                            get: { store.selectedShopOffer?.itemID ?? offer.itemID },
                                            set: { store.updateSelectedShopOfferItemID($0) }
                                        )) {
                                            ForEach(ItemID.allCases, id: \.self) { itemID in
                                                Text(itemID.rawValue).tag(itemID)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                    }

                                    labeledStepper("PRICE", value: Binding(
                                        get: { store.selectedShopOffer?.price ?? offer.price },
                                        set: { store.updateSelectedShopOfferPrice($0) }
                                    ), range: 0...99)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("BLURB")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(palette.label)
                                        TextEditor(text: Binding(
                                            get: { store.selectedShopOffer?.blurb ?? offer.blurb },
                                            set: { store.updateSelectedShopOfferBlurb($0) }
                                        ))
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .scrollContentBackground(.hidden)
                                        .foregroundStyle(palette.text)
                                        .frame(height: 68)
                                        .padding(6)
                                        .background(palette.panelAlt)
                                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                                    }

                                    Toggle(isOn: Binding(
                                        get: { store.selectedShopOffer?.repeatable ?? offer.repeatable },
                                        set: { store.updateSelectedShopOfferRepeatable($0) }
                                    )) {
                                        Text("REPEATABLE")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(palette.label)
                                    }
                                    .toggleStyle(.checkbox)
                                } else {
                                    emptyEditorLabel("NO OFFER IS SELECTED.")
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button("ADD OFFER") {
                                store.addShopOffer()
                            }
                            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                            Button("DROP OFFER") {
                                store.removeSelectedShopOffer()
                            }
                            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                        }
                    }
                } else {
                    emptyEditorLabel("NO SHOP IS AVAILABLE.")
                }
            }
        }
    }

    private var npcRosterPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "NPC ROSTER", palette: palette) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.document.npcs, id: \.id) { npc in
                            Button {
                                store.focusNPC(id: npc.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(npc.name.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("\(npc.id)  @ \(npc.mapID)")
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedNPC?.id == npc.id ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            .frame(width: 280)

            selectionPanel
        }
    }

    private var enemyRosterPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            EditorPanel(title: "ENEMY ROSTER", palette: palette) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.document.enemies, id: \.id) { enemy in
                            Button {
                                store.focusEnemy(id: enemy.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(enemy.name.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text("\(enemy.id)  @ \(enemy.mapID)")
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedEnemy?.id == enemy.id ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            .frame(width: 280)

            selectionPanel
        }
    }

    @ViewBuilder
    private var inspectorFields: some View {
        if let npc = store.selectedNPC {
            Text("NPC INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("NPC ID", text: Binding(
                get: { store.selectedNPC?.id ?? npc.id },
                set: { store.updateSelectedNPCID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedNPC?.name ?? npc.name },
                set: { store.updateSelectedNPCName($0) }
            ))

            labeledField("DIALOGUE", text: Binding(
                get: { store.selectedNPC?.dialogueID ?? npc.dialogueID },
                set: { store.updateSelectedNPCDialogueID($0) }
            ))

            Text("SHOP \(store.selectedNPCShop?.id.uppercased() ?? "NONE")")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.82))

            Button(store.selectedNPCShop == nil ? "CREATE SHOP" : "OPEN SHOP") {
                store.ensureShopForSelectedNPC()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
        } else if let enemy = store.selectedEnemy {
            Text("ENEMY INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("ENEMY ID", text: Binding(
                get: { store.selectedEnemy?.id ?? enemy.id },
                set: { store.updateSelectedEnemyID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedEnemy?.name ?? enemy.name },
                set: { store.updateSelectedEnemyName($0) }
            ))

            HStack(spacing: 8) {
                labeledStepper("HP", value: Binding(
                    get: { store.selectedEnemy?.hp ?? enemy.hp },
                    set: { store.updateSelectedEnemyHP($0) }
                ), range: 1...99)

                labeledStepper("ATK", value: Binding(
                    get: { store.selectedEnemy?.attack ?? enemy.attack },
                    set: { store.updateSelectedEnemyAttack($0) }
                ), range: 0...25)

                labeledStepper("DEF", value: Binding(
                    get: { store.selectedEnemy?.defense ?? enemy.defense },
                    set: { store.updateSelectedEnemyDefense($0) }
                ), range: 0...25)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("AI", selection: Binding(
                    get: { store.selectedEnemy?.ai ?? enemy.ai },
                    set: { store.updateSelectedEnemyAI($0) }
                )) {
                    ForEach([AIKind.idle, .stalk, .guardian, .boss], id: \.self) { ai in
                        Text(ai.rawValue).tag(ai)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let interactable = store.selectedInteractable {
            Text("INTERACTABLE INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("OBJECT ID", text: Binding(
                get: { store.selectedInteractable?.id ?? interactable.id },
                set: { store.updateSelectedInteractableID($0) }
            ))

            labeledField("TITLE", text: Binding(
                get: { store.selectedInteractable?.title ?? interactable.title },
                set: { store.updateSelectedInteractableTitle($0) }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Text("KIND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Kind", selection: Binding(
                    get: { store.selectedInteractable?.kind ?? interactable.kind },
                    set: { store.updateSelectedInteractableKind($0) }
                )) {
                    ForEach(editorInteractablePalette, id: \.kind) { choice in
                        Text(choice.label).tag(choice.kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("REWARD ITEM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Reward Item", selection: Binding(
                    get: { store.selectedInteractable?.rewardItem ?? interactable.rewardItem },
                    set: { store.updateSelectedInteractableRewardItem($0) }
                )) {
                    Text("NONE").tag(Optional<ItemID>.none)
                    ForEach(ItemID.allCases, id: \.self) { itemID in
                        Text(itemID.rawValue).tag(Optional(itemID))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("REQUIRED FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Required Flag", selection: Binding(
                    get: { store.selectedInteractable?.requiredFlag ?? interactable.requiredFlag },
                    set: { store.updateSelectedInteractableRequiredFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GRANTS FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Grants Flag", selection: Binding(
                    get: { store.selectedInteractable?.grantsFlag ?? interactable.grantsFlag },
                    set: { store.updateSelectedInteractableGrantsFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let portal = store.selectedPortal {
            Text("PORTAL INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            VStack(alignment: .leading, spacing: 4) {
                Text("DESTINATION MAP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Destination Map", selection: Binding(
                    get: { store.selectedPortal?.toMap ?? portal.toMap },
                    set: { store.updateSelectedPortalDestinationMap($0) }
                )) {
                    ForEach(store.document.maps, id: \.id) { map in
                        Text(map.name.uppercased()).tag(map.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Button("SYNC TO MAP SPAWN") {
                store.syncSelectedPortalToDestinationSpawn()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

            HStack(spacing: 8) {
                labeledStepper("TO X", value: Binding(
                    get: { store.selectedPortal?.toPosition.x ?? portal.toPosition.x },
                    set: { store.updateSelectedPortalDestinationX($0) }
                ), range: 0...99)

                labeledStepper("TO Y", value: Binding(
                    get: { store.selectedPortal?.toPosition.y ?? portal.toPosition.y },
                    set: { store.updateSelectedPortalDestinationY($0) }
                ), range: 0...99)
            }
        } else {
            Text("NO EDITABLE OBJECT IS SELECTED.")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.80))
        }
    }

    private var footer: some View {
        HStack {
            Text(store.statusLine)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.84))
                .lineLimit(2)
            Spacer()
            Text("EXPORTS TO ~/LIBRARY/APPLICATION SUPPORT/CODEXITMA/ADVENTURES")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.72))
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .padding(6)
                .background(palette.panelAlt)
                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyEditorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.80))
    }

    private func labeledStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                Stepper("", value: value, in: range)
                    .labelsHidden()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .background(palette.panelAlt)
            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tileColor(for glyph: Character) -> Color {
        switch TileFactory.tile(for: glyph).type {
        case .floor:
            return palette.ground
        case .wall:
            return palette.wall
        case .water:
            return palette.water
        case .brush:
            return palette.brush
        case .doorLocked:
            return palette.door
        case .doorOpen:
            return palette.light
        case .shrine:
            return palette.shrine
        case .stairs:
            return palette.light
        case .beacon:
            return palette.beacon
        }
    }

    private func displayGlyph(_ glyph: Character) -> String {
        glyph == " " ? "·" : String(glyph)
    }
}

private struct AdventureEditorPalette {
    let background = Color.black
    let panel = Color(red: 0.03, green: 0.03, blue: 0.02)
    let panelAlt = Color(red: 0.08, green: 0.08, blue: 0.06)
    let text = Color(red: 0.95, green: 0.94, blue: 0.87)
    let label = Color(red: 0.98, green: 0.79, blue: 0.24)
    let title = Color(red: 0.98, green: 0.86, blue: 0.28)
    let border = Color(red: 0.36, green: 0.28, blue: 0.12)
    let selection = Color(red: 0.21, green: 0.18, blue: 0.08)
    let action = Color(red: 0.68, green: 0.40, blue: 0.08)
    let ground = Color(red: 0.36, green: 0.24, blue: 0.09)
    let wall = Color(red: 0.42, green: 0.42, blue: 0.46)
    let water = Color(red: 0.14, green: 0.56, blue: 0.86)
    let brush = Color(red: 0.23, green: 0.74, blue: 0.18)
    let door = Color(red: 0.82, green: 0.62, blue: 0.14)
    let light = Color(red: 0.98, green: 0.90, blue: 0.38)
    let shrine = Color(red: 0.70, green: 0.30, blue: 0.84)
    let beacon = Color(red: 0.99, green: 0.92, blue: 0.34)
}

private struct EditorPanel<Content: View>: View {
    let title: String
    let palette: AdventureEditorPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.title)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
        .overlay(Rectangle().stroke(palette.border, lineWidth: 2))
    }
}

private struct EditorButtonStyle: ButtonStyle {
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? background.opacity(0.75) : background)
            .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.78, blue: 0.18), lineWidth: 1))
    }
}

private struct EditorTileChoice {
    let glyph: Character
    let label: String
}

private struct EditorInteractableChoice {
    let kind: InteractableKind
    let glyph: String
    let label: String
    let color: Color
}

private let editorTilePalette: [EditorTileChoice] = [
    EditorTileChoice(glyph: ".", label: "FLR"),
    EditorTileChoice(glyph: "#", label: "WAL"),
    EditorTileChoice(glyph: "~", label: "WTR"),
    EditorTileChoice(glyph: "\"", label: "BRS"),
    EditorTileChoice(glyph: "+", label: "LCK"),
    EditorTileChoice(glyph: "/", label: "OPN"),
    EditorTileChoice(glyph: "*", label: "SHR"),
    EditorTileChoice(glyph: ">", label: "STA"),
    EditorTileChoice(glyph: "B", label: "BCN"),
    EditorTileChoice(glyph: " ", label: "EMP"),
]

private let editorInteractablePalette: [EditorInteractableChoice] = [
    EditorInteractableChoice(
        kind: .chest,
        glyph: "$",
        label: "CHEST",
        color: Color(red: 0.84, green: 0.56, blue: 0.12)
    ),
    EditorInteractableChoice(
        kind: .shrine,
        glyph: "*",
        label: "SHRINE",
        color: Color(red: 0.78, green: 0.42, blue: 0.94)
    ),
    EditorInteractableChoice(
        kind: .bed,
        glyph: "Z",
        label: "BED",
        color: Color(red: 0.65, green: 0.32, blue: 0.18)
    ),
    EditorInteractableChoice(
        kind: .gate,
        glyph: "+",
        label: "GATE",
        color: Color(red: 0.88, green: 0.72, blue: 0.18)
    ),
    EditorInteractableChoice(
        kind: .beacon,
        glyph: "B",
        label: "BEACON",
        color: Color(red: 0.99, green: 0.94, blue: 0.34)
    ),
    EditorInteractableChoice(
        kind: .plate,
        glyph: "o",
        label: "PLATE",
        color: Color(red: 0.72, green: 0.72, blue: 0.72)
    ),
    EditorInteractableChoice(
        kind: .switchRune,
        glyph: "=",
        label: "RUNE",
        color: Color(red: 0.28, green: 0.74, blue: 0.90)
    ),
]

private extension InteractableKind {
    var editorTitle: String {
        switch self {
        case .npc:
            return "Waystation Speaker"
        case .shrine:
            return "Quiet Shrine"
        case .chest:
            return "Weathered Chest"
        case .bed:
            return "Traveler's Cot"
        case .gate:
            return "Rust Gate"
        case .beacon:
            return "Dormant Beacon"
        case .plate:
            return "Stone Plate"
        case .switchRune:
            return "Rune Switch"
        }
    }

    var defaultLines: [String] {
        switch self {
        case .npc:
            return ["A silent marker waits for a proper NPC record."]
        case .shrine:
            return ["The shrine is cold, but ready to take a new ritual."]
        case .chest:
            return ["The lid groans when it opens."]
        case .bed:
            return ["A rough bed offers a safe place to rest."]
        case .gate:
            return ["The gate's latch is not yet assigned."]
        case .beacon:
            return ["A beacon core could be mounted here one day."]
        case .plate:
            return ["The stone sinks slightly beneath your weight."]
        case .switchRune:
            return ["A rune flickers, waiting for a sequence."]
        }
    }
}
