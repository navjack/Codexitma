import Foundation

extension GameEngine {
    func moveInventorySelection(_ direction: Direction) {
        guard !state.player.inventory.isEmpty else { return }
        let delta: Int
        switch direction {
        case .up, .left:
            delta = -1
        case .down, .right:
            delta = 1
        }
        let count = state.player.inventory.count
        state.inventorySelectionIndex = (state.inventorySelectionIndex + delta + count) % count
        let item = state.player.inventory[state.inventorySelectionIndex]
        state.log("Selected \(item.name).")
    }

    func describeSelectedItem() {
        state.clampInventorySelection()
        guard !state.player.inventory.isEmpty else { return }
        let item = state.player.inventory[state.inventorySelectionIndex]
        if item.isEquippable, let slot = item.slot {
            state.log("\(item.name): \(slot.rawValue) +A\(item.attackBonus) +D\(item.defenseBonus) +L\(item.lanternBonus)")
            return
        }
        switch item.kind {
        case .consumable:
            state.log("\(item.name): restores \(item.value).")
        case .upgrade:
            state.log("\(item.name): permanent boon when used.")
        case .key, .quest:
            state.log("\(item.name): important, but not directly usable.")
        case .equipment:
            state.log("\(item.name): equipable gear.")
        }
    }

    func dropSelectedInventoryItem() {
        state.clampInventorySelection()
        guard !state.player.inventory.isEmpty else {
            state.log("There is nothing to drop.")
            return
        }

        let item = state.player.inventory[state.inventorySelectionIndex]
        if item.kind == .key || item.kind == .quest {
            state.log("\(item.name) is too important to abandon.")
            return
        }

        _ = state.player.inventory.remove(at: state.inventorySelectionIndex)
        state.log("You leave \(item.name) behind.")
        state.clampInventorySelection()
        if state.player.inventory.isEmpty {
            state.mode = .exploration
        }
    }

    func equip(_ item: Item, in slot: EquipmentSlot, returningTo index: Int) {
        let previousItemID = state.player.equipment.itemID(for: slot)
        state.player.equipment.set(item.id, for: slot)
        if let previousItemID,
           let previousItem = content.items[previousItemID],
           state.player.inventory.count < state.player.inventoryCapacity() {
            state.player.inventory.insert(previousItem, at: min(index, state.player.inventory.count))
        }
        state.log("\(item.name) equipped to \(slot.rawValue).")
    }

    func startNewAdventure(with heroClass: HeroClass) {
        let adventureID = state.selectedAdventureID()
        content = library.content(for: adventureID)
        guard let startMap = content.resolvedStartMap() else {
            state.log("That adventure has no valid starting map.")
            state.mode = .title
            return
        }
        let selectedIndex = library.catalog.firstIndex { $0.id == adventureID } ?? 0
        state = Self.makeInitialState(content: content, availableAdventures: library.catalog)
        state.player = Self.makePlayer(for: heroClass, at: startMap)
        state.mode = .exploration
        state.currentAdventureID = adventureID
        state.questFlow = content.questFlow
        state.selectedAdventureIndex = selectedIndex
        let template = heroTemplate(for: heroClass)
        state.log("\(template.title) enters \(content.title).")
    }

    func logSelectedAdventure() {
        state.log("\(state.selectedAdventureTitle()): \(state.selectedAdventureSummary())")
    }
}
