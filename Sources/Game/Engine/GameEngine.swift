import Foundation

final class GameEngine {
    let library: GameContentLibrary
    var content: GameContent
    let saveRepository: SaveRepository
    var turnCounter = 0

    var state: GameState

    init(library: GameContentLibrary, saveRepository: SaveRepository) {
        self.library = library
        let initialAdventure = library.catalog.first?.id ?? .ashesOfMerrow
        self.content = library.content(for: initialAdventure)
        self.saveRepository = saveRepository
        self.state = GameEngine.makeInitialState(content: self.content, availableAdventures: library.catalog)
        for warning in library.loadWarnings {
            self.state.log(warning)
        }
    }

    static func makeInitialState(content: GameContent, availableAdventures: [AdventureCatalogEntry]) -> GameState {
        guard let startMap = content.resolvedStartMap() else {
            preconditionFailure("Adventure \(content.id.rawValue) is missing a valid start map.")
        }
        let player = makePlayer(for: .wayfarer, at: startMap)
        let world = WorldState(
            maps: content.maps,
            npcs: content.initialNPCs,
            enemies: content.initialEnemies,
            openedInteractables: [],
            triggeredEncounters: [],
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

    func beginPlaytest(for adventureID: AdventureID, heroClass: HeroClass = .wayfarer) {
        let resolvedAdventure = library.contains(adventureID)
            ? adventureID
            : (library.catalog.first?.id ?? .ashesOfMerrow)
        content = library.content(for: resolvedAdventure)
        state = GameEngine.makeInitialState(content: content, availableAdventures: library.catalog)
        state.selectedAdventureIndex = library.catalog.firstIndex { $0.id == resolvedAdventure } ?? 0
        startNewAdventure(with: heroClass)
        state.log("Playtest bootstrapped for \(content.title).")
    }

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
        case .pause:
            handlePause(command)
        case .ending:
            if command == .quit || command == .cancel { state.shouldQuit = true }
        default:
            handleExploration(command)
        }
    }

}
