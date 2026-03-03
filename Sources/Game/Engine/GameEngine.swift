import Foundation

final class GameEngine {
    private let content: GameContent
    private let saveRepository: SaveRepository
    private var turnCounter = 0

    var state: GameState

    init(content: GameContent, saveRepository: SaveRepository) {
        self.content = content
        self.saveRepository = saveRepository
        self.state = GameEngine.makeInitialState(content: content)
    }

    static func makeInitialState(content: GameContent) -> GameState {
        let startMap = content.maps["merrow_village"]!
        let player = PlayerState(
            name: "Mira",
            health: 24,
            maxHealth: 24,
            stamina: 12,
            maxStamina: 12,
            attack: 6,
            defense: 3,
            lanternCharge: 8,
            inventory: [itemTable[.healingTonic]!, itemTable[.lanternOil]!],
            position: startMap.spawn,
            currentMapID: startMap.id,
            lastSavePosition: startMap.spawn,
            lastSaveMapID: startMap.id
        )
        let world = WorldState(
            maps: content.maps,
            npcs: content.initialNPCs,
            enemies: content.initialEnemies,
            openedInteractables: []
        )
        return GameState(
            mode: .title,
            player: player,
            world: world,
            quests: QuestState(),
            messages: ["The beacon has gone dark."],
            currentDialogue: nil
        )
    }

    var shouldQuit: Bool { state.shouldQuit }

    func handle(_ command: ActionCommand) {
        switch state.mode {
        case .title:
            handleTitle(command)
        case .exploration:
            handleExploration(command)
        case .dialogue:
            handleDialogue(command)
        case .inventory:
            handleInventory(command)
        case .ending:
            if command == .quit || command == .cancel { state.shouldQuit = true }
        default:
            handleExploration(command)
        }
    }

    private func handleTitle(_ command: ActionCommand) {
        switch command {
        case .newGame, .confirm:
            state = Self.makeInitialState(content: content)
            state.mode = .exploration
            state.log("You wake in Merrow as the valley groans.")
        case .load:
            do {
                let save = try saveRepository.load()
                state.player = save.player
                state.world = save.world
                state.quests = save.quests
                state.playTimeSeconds = save.playTimeSeconds
                state.mode = .exploration
                state.log("You return to the last warm light.")
            } catch SaveError.notFound {
                state.log("No save waits in the ash.")
            } catch {
                state.log("The save file is broken.")
            }
        case .quit, .cancel:
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
            state.mode = .inventory
        case .help:
            state.log(QuestSystem.objective(for: state.quests))
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
        case .interact, .confirm:
            useFirstConsumable()
            state.mode = .exploration
        case .cancel, .openInventory:
            state.mode = .exploration
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
                    playTimeSeconds: state.playTimeSeconds
                )
            )
            state.log("The ember of memory is sealed.")
        } catch {
            state.log("The save ritual failed.")
        }
    }

    private func useFirstConsumable() {
        guard let index = state.player.inventory.firstIndex(where: { $0.kind == .consumable }) else {
            state.log("Your satchel offers no comfort.")
            return
        }
        let item = state.player.inventory.remove(at: index)
        switch item.id {
        case .healingTonic:
            state.player.health = min(state.player.maxHealth, state.player.health + item.value)
            state.log("Warm tonic steadies your pulse.")
        case .lanternOil:
            state.player.lanternCharge += item.value
            state.log("The lantern brightens.")
        default:
            break
        }
    }

    private func resolveCombat(with enemyIndex: Int) {
        state.mode = .combat
        turnCounter += 1
        let playerDamage = CombatSystem.damage(
            attackerAttack: state.player.attack,
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
            defenderDefense: state.player.defense,
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
            state.player.lanternCharge = max(0, state.player.lanternCharge - 1)
            if state.player.lanternCharge == 0 {
                state.log("The fen drinks the last of your lantern.")
            }
            if position.x >= 14 {
                state.quests.set(.fenCrossed)
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
            if state.quests.has(.obtainedLensCore) {
                state.quests.set(.beaconLit)
                state.log("Light races through the tower.")
            } else {
                state.log("A hollow socket awaits the Lens Core.")
            }
        }
    }

    private func grantItem(_ id: ItemID, message: String) {
        guard let item = content.items[id], state.player.inventory.count < 8 else {
            state.log("Your satchel is too full.")
            return
        }
        state.player.inventory.append(item)
        state.log(message)
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

    private func npcDialogueNearPlayer() -> DialogueNode? {
        if state.player.currentMapID == "merrow_village" {
            let elderPos = Position(x: 6, y: 5)
            let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
            if adjacent.contains(elderPos) {
                return content.dialogues["elder_intro"]
            }
        }
        if state.player.currentMapID == "beacon_spire" && state.quests.has(.beaconLit) {
            let keeperPos = Position(x: 12, y: 4)
            let adjacent = Direction.allCases.map { state.player.position + $0.delta } + [state.player.position]
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
}
