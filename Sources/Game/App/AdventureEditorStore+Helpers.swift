import AppKit
import Foundation
import SwiftUI

extension AdventureEditorStore {
    func sanitizeIdentifier(_ value: String) -> String {
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

    func sanitizeFolderName(_ value: String) -> String {
        let safe = sanitizeIdentifier(value)
        return safe.isEmpty ? "new_adventure" : safe
    }

    func resetSecondarySelections() {
        selectedDialogueIndex = 0
        selectedQuestStageIndex = 0
        selectedEncounterIndex = 0
        selectedShopIndex = 0
        selectedShopOfferIndex = 0
    }

    var selectedNPCIndex: Int? {
        guard case .npc(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.npcs.firstIndex(where: { $0.id == id })
    }

    var selectedEnemyIndex: Int? {
        guard case .enemy(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.enemies.firstIndex(where: { $0.id == id })
    }

    var selectedInteractableIndex: Int? {
        guard case .interactable(let id) = selectedCanvasSelection?.kind else { return nil }
        return document.maps[document.selectedMapIndex].interactables.firstIndex(where: { $0.id == id })
    }

    var selectedPortalIndex: Int? {
        guard case .portal(let index) = selectedCanvasSelection?.kind else { return nil }
        guard index >= 0, index < document.maps[document.selectedMapIndex].portals.count else { return nil }
        return index
    }

    var selectedDialogueArrayIndex: Int? {
        guard !document.dialogues.isEmpty else { return nil }
        return max(0, min(selectedDialogueIndex, document.dialogues.count - 1))
    }

    var selectedQuestStageArrayIndex: Int? {
        guard !document.questFlow.stages.isEmpty else { return nil }
        return max(0, min(selectedQuestStageIndex, document.questFlow.stages.count - 1))
    }

    var selectedEncounterArrayIndex: Int? {
        guard !document.encounters.isEmpty else { return nil }
        return max(0, min(selectedEncounterIndex, document.encounters.count - 1))
    }

    var selectedShopArrayIndex: Int? {
        guard !document.shops.isEmpty else { return nil }
        return max(0, min(selectedShopIndex, document.shops.count - 1))
    }

    var selectedShopOfferArrayIndex: Int? {
        guard let shop = selectedShop, !shop.offers.isEmpty else { return nil }
        return max(0, min(selectedShopOfferIndex, shop.offers.count - 1))
    }

    func placeNPC(at position: Position) {
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

    func placeEnemy(at position: Position) {
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

    func placeInteractable(at position: Position) {
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

    func placePortal(at position: Position) {
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

    func setSpawn(at position: Position) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].spawn = position
        selectedCanvasSelection = EditorCanvasSelection(kind: .spawn, position: position)
        statusLine = "SPAWN MOVED TO \(position.x),\(position.y)."
    }

    func erase(at position: Position) {
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

    func selectCanvasObject(at position: Position) {
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

    func nextIdentifier(prefix: String, existing: [String]) -> String {
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

    func suffixNumber(from identifier: String) -> Int {
        let component = identifier.split(separator: "_").last.flatMap { Int($0) }
        return component ?? (document.npcs.count + document.enemies.count + 1)
    }

    func replaceShopOffer(at offerIndex: Int, inShop shopIndex: Int, transform: (ShopOffer) -> ShopOffer) {
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

    func normalizeLines(from value: String) -> [String] {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["..."] : lines
    }

    static func defaultPlaytestLauncher(adventureID: AdventureID) throws {
        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--graphics", "--playtest", adventureID.rawValue]
        try process.run()
    }

    func glyphAt(_ position: Position, in map: EditableMap) -> Character {
        guard position.y >= 0, position.y < map.lines.count else { return "." }
        let row = Array(map.lines[position.y])
        guard position.x >= 0, position.x < row.count else { return "." }
        return row[position.x]
    }

    func displayGlyph(_ glyph: Character) -> String {
        glyph == " " ? "EMP" : String(glyph)
    }

    func tileTypeLabel(_ type: TileType) -> String {
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

    func interactableGlyph(for kind: InteractableKind) -> String {
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

    func color(for ansi: ANSIColor) -> Color {
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

    func color(for kind: InteractableKind) -> Color {
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

    static func makeDocument(entry: AdventureCatalogEntry, content: GameContent) -> EditableAdventureDocument {
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

    static func makeBlankDocument() -> EditableAdventureDocument {
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

    static func makeStarterMapLines() -> [String] {
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

    static func sourceFolderName(for entry: AdventureCatalogEntry) -> String {
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
