import Foundation

extension GameEngine {
    func handlePortalIfNeeded(at position: Position, map: MapDefinition) {
        guard let portal = map.portals.first(where: { $0.from == position }) else { return }
        if let required = portal.requiredFlag, !state.quests.has(required) {
            state.log(portal.blockedMessage ?? "The path rejects you.")
            return
        }
        state.player.currentMapID = portal.toMap
        state.player.position = portal.toPosition
        state.log("You enter \(state.world.maps[portal.toMap]?.name ?? "another place").")
    }

    func isWalkable(_ position: Position, in map: MapDefinition) -> Bool {
        guard position.y >= 0, position.y < map.lines.count else { return false }
        guard position.x >= 0, position.x < map.lines[position.y].count else { return false }
        let char = Array(map.lines[position.y])[position.x]
        let tile = TileFactory.tile(for: char)
        if tile.walkable { return true }
        if tile.type == .doorLocked, state.quests.has(.barrowUnlocked) { return true }
        return false
    }

    func currentTile(at position: Position) -> Tile {
        guard let map = state.world.maps[state.player.currentMapID],
              position.y >= 0, position.y < map.lines.count,
              position.x >= 0, position.x < map.lines[position.y].count else {
            return TileFactory.tile(for: "#")
        }
        let char = Array(map.lines[position.y])[position.x]
        if char == "+", state.quests.has(.barrowUnlocked) {
            return TileFactory.tile(for: "/")
        }
        return TileFactory.tile(for: char)
    }

    func currentEnemyIndex(at position: Position) -> Int? {
        state.world.enemies.firstIndex {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }
    }

    func currentInteractable(at position: Position) -> InteractableDefinition? {
        state.world.maps[state.player.currentMapID]?.interactables.first { $0.position == position }
    }

    func interactableNearPlayer() -> InteractableDefinition? {
        let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
        return state.world.maps[state.player.currentMapID]?.interactables.first { adjacent.contains($0.position) }
    }

    func shopNearPlayer() -> ShopDefinition? {
        guard let npc = npcNearPlayer() else { return nil }
        return content.shops[npc.id]
    }

    func npcNearPlayer() -> NPCState? {
        let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
        return state.world.npcs.first(where: {
            $0.mapID == state.player.currentMapID && adjacent.contains($0.position)
        })
    }

    func npcDialogueNearPlayer() -> DialogueNode? {
        let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
        if let npc = npcNearPlayer() {
            if npc.id == "elder" {
                state.quests.set(.metElder)
            }
            return content.dialogues[npc.dialogueID]
        }

        if state.player.currentMapID == "beacon_spire" && state.quests.has(.beaconLit) {
            let keeperPos = Position(x: 12, y: 4)
            if adjacent.contains(keeperPos), state.world.enemies.contains(where: { $0.id == "keeper" && $0.active }) {
                return content.dialogues["keeper"]
            }
        }
        return nil
    }

    func manhattan(_ a: Position, _ b: Position) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    func stepToward(from: Position, to: Position) -> Position {
        let dx = to.x - from.x
        let dy = to.y - from.y
        if abs(dx) > abs(dy) {
            return Position(x: dx == 0 ? 0 : (dx > 0 ? 1 : -1), y: 0)
        }
        return Position(x: 0, y: dy == 0 ? 0 : (dy > 0 ? 1 : -1))
    }

    func open(shop: ShopDefinition) {
        state.activeShopID = shop.id
        state.shopTitle = "\(shop.merchantName)'s Goods"
        state.shopLines = [
            shop.introLine,
            "Spend marks on supplies, gear, and relic salvage."
        ]
        state.shopOffers = shop.offers
        state.shopDetail = nil
        state.clampShopSelection(offerCount: shop.offers.count)
        state.mode = .shop
        state.log("\(shop.merchantName) opens the trade ledger.")
    }

    func currentShop() -> ShopDefinition? {
        guard let activeShopID = state.activeShopID else { return nil }
        return content.shops.values.first(where: { $0.id == activeShopID })
    }

    func moveShopSelection(_ direction: Direction) {
        guard let shop = currentShop(), !shop.offers.isEmpty else { return }
        let delta: Int = (direction == .up || direction == .left) ? -1 : 1
        let count = shop.offers.count
        state.shopSelectionIndex = (state.shopSelectionIndex + delta + count) % count
        describeSelectedShopOffer()
    }

    func describeSelectedShopOffer() {
        guard let shop = currentShop(), !shop.offers.isEmpty else {
            state.log("This counter is bare.")
            return
        }
        state.clampShopSelection(offerCount: shop.offers.count)
        let offer = shop.offers[state.shopSelectionIndex]
        let itemName = content.items[offer.itemID]?.name ?? offer.itemID.rawValue
        let soldOut = !offer.repeatable && state.world.purchasedShopOffers.contains(offer.id)
        state.shopDetail = offer.blurb
        state.log(soldOut ? "\(itemName) is sold out." : "\(itemName): \(offer.price) marks.")
    }

    func purchaseSelectedShopOffer() {
        guard let shop = currentShop(), !shop.offers.isEmpty else {
            state.log("Nothing here can be bought.")
            return
        }

        state.clampShopSelection(offerCount: shop.offers.count)
        let offer = shop.offers[state.shopSelectionIndex]
        let itemName = content.items[offer.itemID]?.name ?? offer.itemID.rawValue

        if !offer.repeatable && state.world.purchasedShopOffers.contains(offer.id) {
            state.log("\(itemName) has already been claimed.")
            return
        }

        if state.player.marks < offer.price {
            state.log("You need \(offer.price - state.player.marks) more marks.")
            return
        }

        let didReceive = grantShopItem(offer.itemID, purchaseMessage: "You buy \(itemName).")
        guard didReceive else { return }

        state.player.marks -= offer.price
        if !offer.repeatable {
            state.world.purchasedShopOffers.insert(offer.id)
        }
        state.shopDetail = offer.blurb
        state.log("\(shop.merchantName) takes \(offer.price) marks. \(state.player.marks) remain.")
    }

    func grantShopItem(_ id: ItemID, purchaseMessage: String) -> Bool {
        guard let item = content.items[id] else {
            state.log("The merchant's stock ledger is wrong.")
            return false
        }
        if item.isEquippable,
           let slot = item.slot,
           state.player.equipment.itemID(for: slot) == nil {
            state.player.equipment.set(item.id, for: slot)
            state.log(purchaseMessage)
            state.log("\(item.name) is fitted to your \(slot.rawValue).")
            return true
        }
        guard state.player.inventory.count < state.player.inventoryCapacity() else {
            state.log("Your satchel is too full.")
            return false
        }
        state.player.inventory.append(item)
        state.log(purchaseMessage)
        return true
    }
}
