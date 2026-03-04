import Foundation

extension AdventureEditorStore {
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
            return EditorCanvasOverlay(glyph: String(npc.glyphSymbol), style: .ansi(npc.glyphColor))
        }

        if let enemy = document.enemies.first(where: { $0.mapID == mapID && $0.position == position }) {
            return EditorCanvasOverlay(glyph: String(enemy.glyph), style: .ansi(enemy.color))
        }

        if let interactable = currentMap?.interactables.first(where: { $0.position == position }) {
            return EditorCanvasOverlay(
                glyph: interactableGlyph(for: interactable.kind),
                style: .interactable(interactable.kind)
            )
        }

        if currentMap?.portals.contains(where: { $0.from == position }) == true {
            return EditorCanvasOverlay(glyph: ">", style: .portal)
        }

        if currentMap?.spawn == position {
            return EditorCanvasOverlay(glyph: "@", style: .spawn)
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
}
