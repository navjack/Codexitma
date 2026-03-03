import Foundation

final class GameEngine {
    private let library: GameContentLibrary
    private var content: GameContent
    private let saveRepository: SaveRepository
    private var turnCounter = 0

    var state: GameState

    init(library: GameContentLibrary, saveRepository: SaveRepository) {
        self.library = library
        let initialAdventure = library.catalog.first?.id ?? .ashesOfMerrow
        self.content = library.content(for: initialAdventure)
        self.saveRepository = saveRepository
        self.state = GameEngine.makeInitialState(content: self.content, availableAdventures: library.catalog)
    }

    static func makeInitialState(content: GameContent, availableAdventures: [AdventureCatalogEntry]) -> GameState {
        let startMap = content.maps["merrow_village"]!
        let player = makePlayer(for: .wayfarer, at: startMap)
        let world = WorldState(
            maps: content.maps,
            npcs: content.initialNPCs,
            enemies: content.initialEnemies,
            openedInteractables: [],
            activeSwitchSequence: [],
            purchasedShopOffers: []
        )
        return GameState(
            mode: .title,
            player: player,
            world: world,
            quests: QuestState(),
            currentAdventureID: content.id,
            availableAdventures: availableAdventures,
            questFlow: content.questFlow,
            messages: [content.introLine],
            currentDialogue: nil,
            selectedAdventureIndex: availableAdventures.firstIndex { $0.id == content.id } ?? 0
        )
    }

    static func makePlayer(for heroClass: HeroClass, at startMap: MapDefinition) -> PlayerState {
        let template = heroTemplate(for: heroClass)
        let startingInventory = template.startingInventory.compactMap { itemTable[$0] }
        return PlayerState(
            name: "Mira",
            heroClass: template.heroClass,
            traits: template.traits,
            skills: template.skills,
            health: template.baseHealth,
            maxHealth: template.baseHealth,
            stamina: template.baseStamina,
            maxStamina: template.baseStamina,
            attack: template.baseAttack,
            defense: template.baseDefense,
            lanternCharge: template.baseLantern,
            marks: template.startingMarks,
            inventory: startingInventory,
            equipment: template.startingEquipment,
            position: startMap.spawn,
            currentMapID: startMap.id,
            lastSavePosition: startMap.spawn,
            lastSaveMapID: startMap.id
        )
    }

    var shouldQuit: Bool { state.shouldQuit }

    func handle(_ command: ActionCommand) {
        switch state.mode {
        case .title:
            handleTitle(command)
        case .characterCreation:
            handleCharacterCreation(command)
        case .exploration:
            handleExploration(command)
        case .dialogue:
            handleDialogue(command)
        case .inventory:
            handleInventory(command)
        case .shop:
            handleShop(command)
        case .ending:
            if command == .quit || command == .cancel { state.shouldQuit = true }
        default:
            handleExploration(command)
        }
    }

    private func handleTitle(_ command: ActionCommand) {
        let adventureCount = max(state.availableAdventures.count, 1)
        switch command {
        case .move(.left), .move(.up):
            state.selectedAdventureIndex = (state.selectedAdventureIndex - 1 + adventureCount) % adventureCount
            logSelectedAdventure()
        case .move(.right), .move(.down):
            state.selectedAdventureIndex = (state.selectedAdventureIndex + 1) % adventureCount
            logSelectedAdventure()
        case .newGame, .confirm:
            state.mode = .characterCreation
            state.log("Choose a class for \(state.selectedAdventureTitle()), then confirm.")
        case .load:
            do {
                let save = try saveRepository.load()
                guard library.contains(save.adventureID) else {
                    state.log("The saved road is missing. Reinstall that adventure pack first.")
                    return
                }
                content = library.content(for: save.adventureID)
                state.player = save.player
                state.world = save.world
                state.quests = save.quests
                state.playTimeSeconds = save.playTimeSeconds
                state.currentAdventureID = save.adventureID
                state.availableAdventures = library.catalog
                state.questFlow = content.questFlow
                state.selectedAdventureIndex = library.catalog.firstIndex { $0.id == save.adventureID } ?? 0
                state.clearShopPanel()
                state.mode = .exploration
                state.log("You return to the last warm light.")
            } catch SaveError.notFound {
                state.log("No save waits in the ash.")
            } catch {
                state.log("The save file is broken.")
            }
        case .help:
            logSelectedAdventure()
        case .quit, .cancel:
            state.shouldQuit = true
        default:
            break
        }
    }

    private func handleCharacterCreation(_ command: ActionCommand) {
        switch command {
        case .move(.left), .move(.up):
            state.selectedHeroIndex = (state.selectedHeroIndex - 1 + HeroClass.allCases.count) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .move(.right), .move(.down):
            state.selectedHeroIndex = (state.selectedHeroIndex + 1) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .interact, .confirm, .newGame:
            startNewAdventure(with: state.selectedHeroClass())
        case .help:
            let template = heroTemplate(for: state.selectedHeroClass())
            state.log("\(template.title): \(template.summary)")
        case .cancel:
            state.mode = .title
            state.log("The campfire waits while you reconsider.")
        case .quit:
            state.shouldQuit = true
        default:
            break
        }
    }

    private func handleExploration(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            movePlayer(direction)
        case .interact, .confirm:
            interact()
        case .openInventory:
            if state.player.inventory.isEmpty {
                state.log("Your satchel is empty.")
            } else {
                state.clampInventorySelection()
                state.mode = .inventory
            }
        case .help:
            state.log(QuestSystem.objective(for: state.quests, flow: state.questFlow))
        case .save:
            saveAtRestPoint()
        case .cancel:
            state.mode = .pause
            state.log("Press X to quit, or move to continue.")
        case .quit:
            state.shouldQuit = true
        case .load:
            handleTitle(.load)
        case .none:
            break
        case .newGame:
            break
        }
        if state.mode == .exploration {
            state.playTimeSeconds += 1
        }
    }

    private func handleDialogue(_ command: ActionCommand) {
        switch command {
        case .interact, .confirm, .cancel:
            state.currentDialogue = nil
            state.mode = .exploration
            state.log("The silence settles back in.")
        default:
            break
        }
    }

    private func handleInventory(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            moveInventorySelection(direction)
        case .help:
            describeSelectedItem()
        case .interact, .confirm:
            useSelectedInventoryItem()
            state.mode = .exploration
        case .cancel, .openInventory:
            state.mode = .exploration
        default:
            break
        }
    }

    private func handleShop(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            moveShopSelection(direction)
        case .help:
            describeSelectedShopOffer()
        case .interact, .confirm:
            purchaseSelectedShopOffer()
        case .cancel, .openInventory:
            state.clearShopPanel()
            state.mode = .exploration
            state.log("You step back from the counter.")
        case .quit:
            state.shouldQuit = true
        default:
            break
        }
    }

    private func movePlayer(_ direction: Direction) {
        guard let map = state.world.maps[state.player.currentMapID] else { return }
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

    private func interact() {
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

    private func saveAtRestPoint() {
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

    private func useSelectedInventoryItem() {
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

    private func resolveCombat(with enemyIndex: Int) {
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

    private func recoverFromDefeat() {
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

    private func advanceEnemies() {
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

    private func resolveAutoInteractions(at position: Position) {
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

    private func resolve(interactable: InteractableDefinition) {
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

    private func resolvePressurePlate(_ interactable: InteractableDefinition) {
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

    private func resolveSwitchRune(_ interactable: InteractableDefinition) {
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

    private func grantItem(_ id: ItemID, message: String) {
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

    private func moveInventorySelection(_ direction: Direction) {
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

    private func describeSelectedItem() {
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

    private func equip(_ item: Item, in slot: EquipmentSlot, returningTo index: Int) {
        let previousItemID = state.player.equipment.itemID(for: slot)
        state.player.equipment.set(item.id, for: slot)
        if let previousItemID,
           let previousItem = content.items[previousItemID],
           state.player.inventory.count < state.player.inventoryCapacity() {
            state.player.inventory.insert(previousItem, at: min(index, state.player.inventory.count))
        }
        state.log("\(item.name) equipped to \(slot.rawValue).")
    }

    private func startNewAdventure(with heroClass: HeroClass) {
        let adventureID = state.selectedAdventureID()
        content = library.content(for: adventureID)
        let startMap = content.maps["merrow_village"]!
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

    private func logSelectedAdventure() {
        state.log("\(state.selectedAdventureTitle()): \(state.selectedAdventureSummary())")
    }

    private func handlePortalIfNeeded(at position: Position, map: MapDefinition) {
        guard let portal = map.portals.first(where: { $0.from == position }) else { return }
        if let required = portal.requiredFlag, !state.quests.has(required) {
            state.log(portal.blockedMessage ?? "The path rejects you.")
            return
        }
        state.player.currentMapID = portal.toMap
        state.player.position = portal.toPosition
        state.log("You enter \(state.world.maps[portal.toMap]?.name ?? "another place").")
    }

    private func isWalkable(_ position: Position, in map: MapDefinition) -> Bool {
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

    private func currentEnemyIndex(at position: Position) -> Int? {
        state.world.enemies.firstIndex {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }
    }

    private func currentInteractable(at position: Position) -> InteractableDefinition? {
        state.world.maps[state.player.currentMapID]?.interactables.first { $0.position == position }
    }

    private func interactableNearPlayer() -> InteractableDefinition? {
        let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
        return state.world.maps[state.player.currentMapID]?.interactables.first { adjacent.contains($0.position) }
    }

    private func shopNearPlayer() -> ShopDefinition? {
        guard let npc = npcNearPlayer() else { return nil }
        return content.shops[npc.id]
    }

    private func npcNearPlayer() -> NPCState? {
        let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
        return state.world.npcs.first(where: {
            $0.mapID == state.player.currentMapID && adjacent.contains($0.position)
        })
    }

    private func npcDialogueNearPlayer() -> DialogueNode? {
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

    private func manhattan(_ a: Position, _ b: Position) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func stepToward(from: Position, to: Position) -> Position {
        let dx = to.x - from.x
        let dy = to.y - from.y
        if abs(dx) > abs(dy) {
            return Position(x: dx == 0 ? 0 : (dx > 0 ? 1 : -1), y: 0)
        }
        return Position(x: 0, y: dy == 0 ? 0 : (dy > 0 ? 1 : -1))
    }

    private func open(shop: ShopDefinition) {
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

    private func currentShop() -> ShopDefinition? {
        guard let activeShopID = state.activeShopID else { return nil }
        return content.shops.values.first(where: { $0.id == activeShopID })
    }

    private func moveShopSelection(_ direction: Direction) {
        guard let shop = currentShop(), !shop.offers.isEmpty else { return }
        let delta: Int = (direction == .up || direction == .left) ? -1 : 1
        let count = shop.offers.count
        state.shopSelectionIndex = (state.shopSelectionIndex + delta + count) % count
        describeSelectedShopOffer()
    }

    private func describeSelectedShopOffer() {
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

    private func purchaseSelectedShopOffer() {
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

    private func grantShopItem(_ id: ItemID, purchaseMessage: String) -> Bool {
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
