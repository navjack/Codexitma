import AppKit
import Foundation
import SwiftUI

enum LaunchMode: Equatable {
    case graphics
    case terminal

    static func parse(arguments: [String]) -> LaunchMode {
        if arguments.contains("--terminal") {
            return .terminal
        }
        return .graphics
    }
}

enum GraphicsVisualTheme: String, CaseIterable, Equatable {
    case gemstone
    case ultima
    case depth3D

    var displayName: String {
        switch self {
        case .gemstone:
            return "Gemstone"
        case .ultima:
            return "Ultima"
        case .depth3D:
            return "Depth 3D"
        }
    }

    var summary: String {
        switch self {
        case .gemstone:
            return "Bright chamber borders, black void framing, and chunkier sprites."
        case .ultima:
            return "Cleaner overworld boards with flatter tiles and a stricter classic field look."
        case .depth3D:
            return "A first-person pseudo-3D dungeon view that reads the same live map."
        }
    }

    func next() -> GraphicsVisualTheme {
        switch self {
        case .gemstone:
            return .ultima
        case .ultima:
            return .depth3D
        case .depth3D:
            return .gemstone
        }
    }
}

@MainActor
final class GameSessionController: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var visualTheme: GraphicsVisualTheme = .gemstone

    private let library: GameContentLibrary
    private let engine: GameEngine
    private let preferenceStore: GraphicsPreferenceStore
    private let soundEngine: AppleIISoundEngine

    init(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: AppleIISoundEngine = .shared
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

    func send(_ command: ActionCommand) {
        let previous = state
        let resolved = resolvedCommand(for: command)
        engine.handle(resolved)
        state = engine.state
        playSound(for: resolved, previous: previous, current: state)
        if state.shouldQuit {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
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

    func openEditorForCurrentContext() {
        AdventureEditorLauncher.present(library: library, initialAdventureID: editorTargetAdventureID())
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

@MainActor
enum GraphicsGameLauncher {
    private static var retainedDelegate: GraphicsAppDelegate?

    static func run(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil
    ) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let session = GameSessionController(
            library: library,
            saveRepository: saveRepository,
            playtestAdventureID: playtestAdventureID
        )
        let delegate = GraphicsAppDelegate(session: session)
        retainedDelegate = delegate
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

final class GraphicsAppDelegate: NSObject, NSApplicationDelegate {
    private let session: GameSessionController
    private var window: NSWindow?

    init(session: GameSessionController) {
        self.session = session
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 960, height: 680)
        window.center()
        window.contentView = NSHostingView(rootView: GameRootView(session: session))
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
