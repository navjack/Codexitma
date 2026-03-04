import Foundation

extension GameEngine {
    func handleTitle(_ command: ActionCommand) {
        let adventureCount = max(state.availableAdventures.count, 1)
        switch command {
        case .move(.left), .move(.up):
            state.selectedAdventureIndex = (state.selectedAdventureIndex - 1 + adventureCount) % adventureCount
            logSelectedAdventure()
        case .move(.right), .move(.down):
            state.selectedAdventureIndex = (state.selectedAdventureIndex + 1) % adventureCount
            logSelectedAdventure()
        case .turnLeft:
            state.selectedAdventureIndex = (state.selectedAdventureIndex - 1 + adventureCount) % adventureCount
            logSelectedAdventure()
        case .turnRight:
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
        case .moveBackward:
            break
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
}
