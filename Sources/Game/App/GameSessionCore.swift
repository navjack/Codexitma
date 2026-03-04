import Foundation

@MainActor
final class SharedGameSession {
    private let library: GameContentLibrary
    private let engine: GameEngine
    private let preferenceStore: GraphicsPreferenceStore
    private let soundEngine: any GameSoundPlayback

    private(set) var state: GameState
    private(set) var visualTheme: GraphicsVisualTheme

    init(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: any GameSoundPlayback = SilentGameSoundEngine.shared
    ) {
        self.library = library
        self.preferenceStore = preferenceStore
        self.soundEngine = soundEngine
        let engine = GameEngine(library: library, saveRepository: saveRepository)
        if let playtestAdventureID {
            engine.beginPlaytest(for: playtestAdventureID)
        }
        self.engine = engine
        self.state = engine.state
        self.visualTheme = preferenceStore.loadTheme()
        soundEngine.play(.introMusic)
    }

    var sceneSnapshot: GraphicsSceneSnapshot {
        GraphicsSceneSnapshotBuilder.build(state: state, visualTheme: visualTheme)
    }

    func send(_ command: ActionCommand) {
        let previous = state
        let resolved = resolvedCommand(for: command)
        engine.handle(resolved)
        state = engine.state
        playSound(for: resolved, previous: previous, current: state)
    }

    func cycleVisualTheme() {
        visualTheme = visualTheme.next()
        preferenceStore.saveTheme(visualTheme)
    }

    func selectVisualTheme(_ theme: GraphicsVisualTheme) {
        visualTheme = theme
        preferenceStore.saveTheme(theme)
    }

    func canOpenEditorFromCurrentMode() -> Bool {
        state.mode != .ending
    }

    func editorTargetAdventureID() -> AdventureID {
        switch state.mode {
        case .title, .characterCreation:
            return state.selectedAdventureID()
        default:
            return state.currentAdventureID
        }
    }

    func editorConfirmationLines() -> [String] {
        let adventureID = editorTargetAdventureID()
        let isExternal = library.entry(for: adventureID)?.folder.contains("/") == true
        var lines: [String] = []

        if isExternal {
            lines.append("THIS OPENS THE RESOLVED USER PACK OR OVERRIDE FOR \(adventureID.rawValue.uppercased()).")
            lines.append("SAVES WILL WRITE BACK INTO THAT EXISTING EXTERNAL PACK FOLDER.")
        } else {
            lines.append("THIS OPENS THE BUNDLED ADVENTURE \(adventureID.rawValue.uppercased()) IN THE EDITOR.")
            lines.append("SAVES WILL CREATE OR UPDATE A SAFE EXTERNAL OVERRIDE. THE APP BUNDLE STAYS READ-ONLY.")
        }

        if state.mode != .title && state.mode != .characterCreation {
            lines.append("YOUR CURRENT RUN STAYS OPEN IN THIS WINDOW WHILE THE EDITOR OPENS.")
        }

        return lines
    }

    private func resolvedCommand(for command: ActionCommand) -> ActionCommand {
        guard visualTheme == .depth3D, state.mode == .exploration else {
            return command
        }

        switch command {
        case .move(.up):
            return .move(state.player.facing)
        case .move(.down):
            return .moveBackward
        case .move(.left):
            return .turnLeft
        case .move(.right):
            return .turnRight
        default:
            return command
        }
    }

    private func playSound(for command: ActionCommand, previous: GameState, current: GameState) {
        if previous.mode == .title && current.mode == .characterCreation {
            soundEngine.play(.menuConfirm)
            return
        }

        if previous.mode == .characterCreation && current.mode == .exploration {
            soundEngine.play(.menuConfirm)
            return
        }

        if isMovementCommand(command) {
            if previous.player.position != current.player.position {
                soundEngine.play(.walk)
                return
            }

            let enemyRosterChanged = previous.world.enemies != current.world.enemies
            let healthChanged = previous.player.health != current.player.health
            if enemyRosterChanged || healthChanged {
                soundEngine.play(.attack)
                return
            }
        }

        if isTurnCommand(command), previous.player.facing != current.player.facing {
            soundEngine.play(.menuConfirm)
            return
        }

        let usedItem = previous.mode == .inventory && current.mode == .exploration &&
            (
                previous.player.inventory.count != current.player.inventory.count ||
                previous.player.equipment != current.player.equipment ||
                previous.player.health != current.player.health ||
                previous.player.lanternCharge != current.player.lanternCharge
            )
        if usedItem {
            soundEngine.play(.useItem)
            return
        }

        let boughtFromShop = previous.mode == .shop && current.mode == .shop &&
            (
                previous.player.marks != current.player.marks ||
                previous.player.inventory.count != current.player.inventory.count ||
                previous.player.equipment != current.player.equipment
            )
        if boughtFromShop {
            soundEngine.play(.useItem)
            return
        }

        if (command == .interact || command == .confirm), previous.mode == .exploration, current.mode == .shop {
            soundEngine.play(.menuConfirm)
            return
        }

        if command == .interact || command == .confirm, previous.mode == .exploration, current.mode == .dialogue {
            soundEngine.play(.menuConfirm)
        }
    }

    private func isMovementCommand(_ command: ActionCommand) -> Bool {
        switch command {
        case .move, .moveBackward:
            return true
        default:
            return false
        }
    }

    private func isTurnCommand(_ command: ActionCommand) -> Bool {
        switch command {
        case .turnLeft, .turnRight:
            return true
        default:
            return false
        }
    }
}
