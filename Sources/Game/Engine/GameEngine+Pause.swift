import Foundation

extension GameEngine {
    func handlePause(_ command: ActionCommand) {
        switch command {
        case .move(let direction):
            movePauseSelection(direction)
        case .turnLeft:
            movePauseSelection(.left)
        case .turnRight:
            movePauseSelection(.right)
        case .moveBackward:
            movePauseSelection(.up)
        case .interact, .confirm:
            executePauseSelection()
        case .save:
            _ = persistCurrentRun(
                updateRestPoint: true,
                successMessage: "The current road is sealed into memory.",
                failureMessage: "The save ritual failed."
            )
        case .cancel:
            resumeFromPause()
        case .quit:
            state.shouldQuit = true
        default:
            break
        }
    }

    private func movePauseSelection(_ direction: Direction) {
        let options = PauseMenuOption.allCases
        guard !options.isEmpty else {
            state.pauseSelectionIndex = 0
            return
        }

        let delta: Int
        switch direction {
        case .up, .left:
            delta = -1
        case .down, .right:
            delta = 1
        }

        state.pauseSelectionIndex = (state.pauseSelectionIndex + delta + options.count) % options.count
        state.log("\(state.selectedPauseOption().label) selected.")
    }

    private func executePauseSelection() {
        switch state.selectedPauseOption() {
        case .resume:
            resumeFromPause()
        case .saveAndReturnToTitle:
            let saved = persistCurrentRun(
                updateRestPoint: true,
                successMessage: "The current road is sealed into memory.",
                failureMessage: "The save ritual failed."
            )
            if saved {
                returnToTitle(logMessage: "You return to the title road with your progress sealed.")
            }
        case .returnToTitle:
            returnToTitle(logMessage: "You step back to the title road.")
        case .quitGame:
            state.shouldQuit = true
        }
    }

    private func resumeFromPause() {
        state.mode = .exploration
        state.pauseSelectionIndex = 0
        state.log("You return to the road.")
    }

    private func returnToTitle(logMessage: String) {
        let selectedIndex = library.catalog.firstIndex { $0.id == state.currentAdventureID } ?? state.selectedAdventureIndex
        state.mode = .title
        state.selectedAdventureIndex = selectedIndex
        state.pauseSelectionIndex = 0
        state.inventorySelectionIndex = 0
        state.currentDialogue = nil
        state.clearShopPanel()
        state.log(logMessage)
    }
}
