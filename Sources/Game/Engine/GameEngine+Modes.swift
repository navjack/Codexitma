import Foundation

extension GameEngine {
    func handleTitle(_ command: ActionCommand) {
        let adventureCount = max(state.availableAdventures.count, 1)
        switch command {
        case .move(.left):
            state.selectedAdventureIndex = (state.selectedAdventureIndex - 1 + adventureCount) % adventureCount
            logSelectedAdventure()
        case .move(.right):
            state.selectedAdventureIndex = (state.selectedAdventureIndex + 1) % adventureCount
            logSelectedAdventure()
        case .move(.up):
            moveTitleSelection(step: -1)
        case .move(.down):
            moveTitleSelection(step: 1)
        case .turnLeft:
            state.selectedAdventureIndex = (state.selectedAdventureIndex - 1 + adventureCount) % adventureCount
            logSelectedAdventure()
        case .turnRight:
            state.selectedAdventureIndex = (state.selectedAdventureIndex + 1) % adventureCount
            logSelectedAdventure()
        case .newGame:
            state.titleSelectionIndex = 0
            activateSelectedTitleOption()
        case .interact, .confirm:
            activateSelectedTitleOption()
        case .load:
            loadSavedAdventure()
        case .help:
            state.log("\(state.selectedTitleOption().label): \(state.selectedTitleOption().detail)")
        case .quit, .cancel:
            state.shouldQuit = true
        case .moveBackward:
            moveTitleSelection(step: 1)
        default:
            break
        }
    }

    func handleCharacterCreation(_ command: ActionCommand) {
        switch command {
        case .move(.left), .move(.up):
            state.selectedHeroIndex = (state.selectedHeroIndex - 1 + HeroClass.allCases.count) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .move(.right), .move(.down):
            state.selectedHeroIndex = (state.selectedHeroIndex + 1) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .turnLeft:
            state.selectedHeroIndex = (state.selectedHeroIndex - 1 + HeroClass.allCases.count) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .turnRight:
            state.selectedHeroIndex = (state.selectedHeroIndex + 1) % HeroClass.allCases.count
            state.log("\(heroTemplate(for: state.selectedHeroClass()).title) selected.")
        case .interact, .confirm, .newGame:
            startNewAdventure(with: state.selectedHeroClass())
        case .help:
            let template = heroTemplate(for: state.selectedHeroClass())
            state.log("\(template.title): \(template.summary)")
        case .cancel:
            state.mode = .title
            state.titleSelectionIndex = 0
            state.log("The campfire waits while you reconsider.")
        case .quit:
            state.shouldQuit = true
        case .moveBackward:
            break
        default:
            break
        }
    }

    func handleExploration(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            movePlayer(direction)
        case .turnLeft:
            state.player.facing = state.player.facing.leftTurn
            state.log("You turn left.")
        case .turnRight:
            state.player.facing = state.player.facing.rightTurn
            state.log("You turn right.")
        case .moveBackward:
            movePlayer(state.player.facing.opposite, preserveFacing: true)
        case .interact, .confirm:
            interact()
        case .openInventory:
            if state.player.inventory.isEmpty {
                state.log("Your satchel is empty.")
            } else {
                state.clampInventorySelection()
                state.mode = .inventory
            }
        case .dropInventoryItem:
            state.log("Open your pack before you drop anything.")
        case .help:
            state.log(QuestSystem.objective(for: state.quests, flow: state.questFlow))
        case .save:
            saveAtRestPoint()
        case .cancel:
            state.mode = .pause
            state.pauseSelectionIndex = 0
            state.log("Pause menu open. Resume, save and return, or leave the road.")
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

    func handleDialogue(_ command: ActionCommand) {
        switch command {
        case .interact, .confirm, .cancel:
            state.currentDialogue = nil
            state.mode = .exploration
            state.log("The silence settles back in.")
        default:
            break
        }
    }

    func handleInventory(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            moveInventorySelection(direction)
        case .turnLeft:
            moveInventorySelection(.left)
        case .turnRight:
            moveInventorySelection(.right)
        case .moveBackward:
            moveInventorySelection(.up)
        case .dropInventoryItem:
            dropSelectedInventoryItem()
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

    func handleShop(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            moveShopSelection(direction)
        case .turnLeft:
            moveShopSelection(.left)
        case .turnRight:
            moveShopSelection(.right)
        case .moveBackward:
            moveShopSelection(.up)
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

    private func moveTitleSelection(step: Int) {
        let options = TitleMenuOption.allCases
        guard !options.isEmpty else {
            state.titleSelectionIndex = 0
            return
        }

        state.titleSelectionIndex = (state.titleSelectionIndex + step + options.count) % options.count
        state.log("\(state.selectedTitleOption().label) selected.")
    }

    private func activateSelectedTitleOption() {
        switch state.selectedTitleOption() {
        case .startNewGame:
            state.mode = .characterCreation
            state.selectedHeroIndex = 0
            state.log("Choose a class for \(state.selectedAdventureTitle()), then begin the road.")
        case .loadSave:
            loadSavedAdventure()
        case .quitGame:
            state.shouldQuit = true
        }
    }

    private func loadSavedAdventure() {
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
            state.titleSelectionIndex = TitleMenuOption.allCases.firstIndex(of: .startNewGame) ?? 0
            state.clearShopPanel()
            state.mode = .exploration
            state.log("You return to the last warm light.")
        } catch SaveError.notFound {
            state.log("No save waits in the ash.")
        } catch {
            state.log("The save file is broken.")
        }
    }
}
