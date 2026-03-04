import Foundation

@MainActor
final class AdventureEditorStore: EditorObservableObject {
    @EditorPublished var selectedCatalogID: AdventureID?
    @EditorPublished var document: EditableAdventureDocument
    @EditorPublished var selectedContentTab: EditorContentTab = .maps
    @EditorPublished var selectedTool: EditorTool = .terrain
    @EditorPublished var selectedGlyph: Character = "#"
    @EditorPublished var selectedInteractableKind: InteractableKind = .chest
    @EditorPublished var selectedCanvasSelection: EditorCanvasSelection?
    @EditorPublished var selectedDialogueIndex = 0
    @EditorPublished var selectedQuestStageIndex = 0
    @EditorPublished var selectedEncounterIndex = 0
    @EditorPublished var selectedShopIndex = 0
    @EditorPublished var selectedShopOfferIndex = 0
    @EditorPublished var validationMessages: [String] = []
    @EditorPublished var statusLine = "READY. FORK AN ADVENTURE OR CREATE A NEW TEMPLATE."

    let catalog: [AdventureCatalogEntry]

    let library: GameContentLibrary
    let exporter: AdventurePackExporter
    let playtestLauncher: @MainActor (AdventureID) throws -> Void

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

}
