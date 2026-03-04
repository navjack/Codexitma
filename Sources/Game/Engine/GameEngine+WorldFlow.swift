import Foundation

extension GameEngine {
    func movePlayer(_ direction: Direction, preserveFacing: Bool = false) {
        guard let map = state.world.maps[state.player.currentMapID] else { return }
        if !preserveFacing {
            state.player.facing = direction
        }
        let target = state.player.position + direction.delta

        if let enemyIndex = currentEnemyIndex(at: target) {
            resolveCombat(with: enemyIndex)
            return
        }

        guard isWalkable(target, in: map) else {
            state.log("Stone and shadow refuse the way.")
            return
        }

        state.player.position = target
        handlePortalIfNeeded(at: target, map: map)
        resolveAutoInteractions(at: target)
        advanceEnemies()
    }

    func interact() {
        if let shop = shopNearPlayer() {
            open(shop: shop)
            return
        }

        if let dialogue = npcDialogueNearPlayer() {
            state.currentDialogue = dialogue
            state.mode = .dialogue
            if dialogue.id == "elder_intro" {
                state.quests.set(.metElder)
            }
            return
        }

        if let interactable = interactableNearPlayer() {
            resolve(interactable: interactable)
            return
        }

        state.log("There is only cold wind here.")
    }

    func saveAtRestPoint() {
        guard currentInteractable(at: state.player.position)?.kind == .bed || currentTile(at: state.player.position).type == .beacon else {
            state.log("Only beds and beacons hold a safe memory.")
            return
        }
        state.player.lastSavePosition = state.player.position
        state.player.lastSaveMapID = state.player.currentMapID
        do {
            try saveRepository.save(
                SaveGame(
                    player: state.player,
                    world: state.world,
                    quests: state.quests,
                    playTimeSeconds: state.playTimeSeconds,
                    adventureID: state.currentAdventureID
                )
            )
            state.log("The ember of memory is sealed.")
        } catch {
            state.log("The save ritual failed.")
        }
    }

    func useSelectedInventoryItem() {
        state.clampInventorySelection()
        guard !state.player.inventory.isEmpty else {
            state.log("Your satchel offers no comfort.")
            return
        }
        let index = state.inventorySelectionIndex
        let item = state.player.inventory.remove(at: index)
        switch item.id {
        case .healingTonic:
            state.player.health = min(state.player.maxHealth, state.player.health + state.player.tonicHealingAmount(base: item.value))
            state.log("Warm tonic steadies your pulse.")
        case .lanternOil:
            state.player.lanternCharge += item.value
            state.log("The lantern brightens.")
        case .charmFragment:
            state.player.maxHealth += 2
            state.player.health = min(state.player.maxHealth, state.player.health + 2)
            state.player.attack += 1
            state.log("The fragment fuses into your gear. You feel hardier.")
        default:
            if item.isEquippable, let slot = item.slot {
                equip(item, in: slot, returningTo: index)
            } else {
                state.player.inventory.insert(item, at: min(index, state.player.inventory.count))
                state.log("\(item.name) cannot be used directly.")
            }
        }
        state.clampInventorySelection()
    }

    func resolveCombat(with enemyIndex: Int) {
        state.mode = .combat
        turnCounter += 1
        let playerDamage = CombatSystem.damage(
            attackerAttack: state.player.effectiveAttack(),
            defenderDefense: state.world.enemies[enemyIndex].defense,
            turnIndex: turnCounter
        )
        state.world.enemies[enemyIndex].hp -= playerDamage
        let enemyName = state.world.enemies[enemyIndex].name
        state.log("You strike \(enemyName) for \(playerDamage).")

        if state.world.enemies[enemyIndex].hp <= 0 {
            state.world.enemies[enemyIndex].active = false
            state.log("\(enemyName) falls into dust.")
            if state.world.enemies[enemyIndex].id == "keeper" {
                state.quests.set(.keeperDefeated)
                state.mode = .ending
                state.log("Shadow breaks beneath the beacon.")
                return
            }
            state.mode = .exploration
            if state.world.enemies[enemyIndex].id == "sentinel_1" {
                grantItem(.lensCore, message: "The Lens Core hums in your palm.")
                state.quests.set(.obtainedLensCore)
            }
            return
        }

        let enemyDamage = CombatSystem.damage(
            attackerAttack: state.world.enemies[enemyIndex].attack,
            defenderDefense: state.player.effectiveDefense(),
            turnIndex: turnCounter + 1
        )
        state.player.health -= enemyDamage
        state.log("\(enemyName) answers for \(enemyDamage).")

        if state.player.health <= 0 {
            recoverFromDefeat()
        } else {
            state.mode = .exploration
        }
    }

    func recoverFromDefeat() {
        state.mode = .gameOver
        state.player.health = max(1, state.player.maxHealth / 2)
        state.player.position = state.player.lastSavePosition
        state.player.currentMapID = state.player.lastSaveMapID
        let lossCount = Int(Double(state.player.inventory.filter { $0.kind == .consumable }.count) * 0.1)
        if lossCount > 0 {
            var removed = 0
            state.player.inventory.removeAll {
                guard removed < lossCount, $0.kind == .consumable else { return false }
                removed += 1
                return true
            }
        }
        state.log("You wake at the last safe ember, diminished but living.")
        state.mode = .exploration
    }

    func advanceEnemies() {
        guard state.mode == .exploration else { return }
        for index in state.world.enemies.indices {
            guard state.world.enemies[index].active, state.world.enemies[index].mapID == state.player.currentMapID else { continue }
            let distance = manhattan(state.world.enemies[index].position, state.player.position)
            guard distance <= 6 else { continue }
            let step = stepToward(from: state.world.enemies[index].position, to: state.player.position)
            let target = state.world.enemies[index].position + step
            if target == state.player.position {
                resolveCombat(with: index)
                return
            }
            if isWalkable(target, in: state.world.maps[state.player.currentMapID]!) && currentEnemyIndex(at: target) == nil {
                state.world.enemies[index].position = target
            }
        }
    }

    func resolveAutoInteractions(at position: Position) {
        let tile = currentTile(at: position)
        if tile.type == .beacon && state.quests.has(.obtainedLensCore) {
            state.quests.set(.beaconLit)
            state.log("The beacon chamber accepts the Lens Core.")
        }
        if state.player.currentMapID == "black_fen" {
            let drain = state.player.hasSkill(.trailcraft) && state.playTimeSeconds.isMultiple(of: 2) ? 0 : 1
            if drain > 0 {
                state.player.lanternCharge = max(0, state.player.lanternCharge - drain)
                if state.player.lanternCharge == 0 {
                    state.log("The fen drinks the last of your lantern.")
                }
            }
        }
    }

    func resolve(interactable: InteractableDefinition) {
        if let required = interactable.requiredFlag, !state.quests.has(required) {
            state.log("The way stays shut.")
            return
        }

        switch interactable.kind {
        case .npc:
            if let dialogue = content.dialogues[interactable.id] {
                state.currentDialogue = dialogue
                state.mode = .dialogue
            }
        case .shrine:
            if state.world.openedInteractables.contains(interactable.id) {
                state.log("This shrine already burns.")
                return
            }
            state.world.openedInteractables.insert(interactable.id)
            if let flag = interactable.grantsFlag {
                state.quests.set(flag)
            }
            state.player.lanternCharge += 2
            state.log(interactable.lines.first ?? "The shrine wakes.")
        case .chest:
            if state.world.openedInteractables.contains(interactable.id) {
                state.log("Only splinters remain.")
                return
            }
            state.world.openedInteractables.insert(interactable.id)
            if let reward = interactable.rewardItem {
                grantItem(reward, message: interactable.lines.first ?? "You find something useful.")
            }
            if let reward = interactable.rewardMarks, reward > 0 {
                let message = interactable.rewardItem == nil
                    ? (interactable.lines.first ?? "You find a cache of old coin.")
                    : nil
                grantMarks(reward, message: message)
            }
        case .bed:
            state.player.lastSavePosition = state.player.position
            state.player.lastSaveMapID = state.player.currentMapID
            state.player.health = state.player.maxHealth
            state.player.stamina = state.player.maxStamina
            state.log("A brief rest steadies the body.")
        case .gate:
            if state.quests.has(.southShrineLit) && state.quests.has(.orchardShrineLit) {
                state.quests.set(.barrowUnlocked)
                state.log("The sealed gate grinds open.")
            } else {
                state.log(interactable.lines.first ?? "The gate will not move.")
            }
        case .beacon:
            if state.quests.has(.beaconLit) {
                state.log("The beacon already commands the night.")
                return
            }
            guard state.world.openedInteractables.contains("spire_mirrors_aligned") else {
                state.log("Dark mirrors starve the beacon of focus.")
                return
            }
            if state.quests.has(.obtainedLensCore) {
                state.quests.set(.beaconLit)
                state.log("Light races through the tower.")
            } else {
                state.log("A hollow socket awaits the Lens Core.")
            }
        case .plate:
            resolvePressurePlate(interactable)
        case .switchRune:
            resolveSwitchRune(interactable)
        }
    }

    func resolvePressurePlate(_ interactable: InteractableDefinition) {
        if state.world.openedInteractables.contains(interactable.id) {
            state.log("The plate is already sunk into the stone.")
            return
        }
        state.world.openedInteractables.insert(interactable.id)
        state.log(interactable.lines.first ?? "A hidden weight shifts below.")

        let fenPlates: Set<String> = ["fen_plate_west", "fen_plate_east"]
        if fenPlates.isSubset(of: state.world.openedInteractables) {
            state.quests.set(.fenCrossed)
            state.world.openedInteractables.insert("fen_causeway_raised")
            state.log("Stone teeth rise from the fen and form a safe causeway.")
        }
    }

    func resolveSwitchRune(_ interactable: InteractableDefinition) {
        let solution = ["spire_switch_sun", "spire_switch_moon", "spire_switch_star"]

        if state.world.openedInteractables.contains("spire_mirrors_aligned") {
            state.log("The mirror lattice is already aligned.")
            return
        }

        state.world.activeSwitchSequence.append(interactable.id)
        if !solution.starts(with: state.world.activeSwitchSequence) {
            if state.player.hasSkill(.runeSight) {
                _ = state.world.activeSwitchSequence.popLast()
                state.log("Rune sight preserves the mirrors' partial alignment.")
            } else {
                state.world.activeSwitchSequence = interactable.id == solution.first ? [interactable.id] : []
                state.log("The tower hum snaps out of tune. The mirrors reset.")
            }
            return
        }

        if state.world.activeSwitchSequence.count == solution.count {
            state.world.openedInteractables.insert("spire_mirrors_aligned")
            state.world.activeSwitchSequence = []
            state.log("The mirrors lock in place above the lens cradle.")
            return
        }

        state.log(interactable.lines.first ?? "A distant mirror answers the rune.")
    }

    func grantItem(_ id: ItemID, message: String) {
        guard let item = content.items[id] else {
            state.log("The relic dissolves before you can claim it.")
            return
        }
        if item.isEquippable,
           let slot = item.slot,
           state.player.equipment.itemID(for: slot) == nil {
            state.player.equipment.set(item.id, for: slot)
            state.log(message)
            state.log("\(item.name) is fitted to your \(slot.rawValue).")
            return
        }
        guard state.player.inventory.count < state.player.inventoryCapacity() else {
            state.log("Your satchel is too full.")
            return
        }
        state.player.inventory.append(item)
        state.log(message)
    }

    func grantMarks(_ amount: Int, message: String?) {
        guard amount > 0 else { return }
        state.player.marks += amount
        if let message {
            state.log(message)
        }
        state.log("You gain \(amount) marks.")
    }

}
