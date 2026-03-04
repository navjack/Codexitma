#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

@MainActor
final class GameSessionController: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var visualTheme: GraphicsVisualTheme = .gemstone

    private let library: GameContentLibrary
    private let core: SharedGameSession

    init(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: AppleIISoundEngine = .shared
    ) {
        self.library = library
        let core = SharedGameSession(
            library: library,
            saveRepository: saveRepository,
            playtestAdventureID: playtestAdventureID,
            preferenceStore: preferenceStore,
            soundEngine: soundEngine
        )
        self.core = core
        self.state = core.state
        self.visualTheme = core.visualTheme
    }

    func send(_ command: ActionCommand) {
        core.send(command)
        refresh()
        if state.shouldQuit {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func cycleVisualTheme() {
        core.cycleVisualTheme()
        refresh()
    }

    func selectVisualTheme(_ theme: GraphicsVisualTheme) {
        core.selectVisualTheme(theme)
        refresh()
    }

    var sceneSnapshot: GraphicsSceneSnapshot {
        core.sceneSnapshot
    }

    func canOpenEditorFromCurrentMode() -> Bool {
        core.canOpenEditorFromCurrentMode()
    }

    func editorTargetAdventureID() -> AdventureID {
        core.editorTargetAdventureID()
    }

    func editorConfirmationLines() -> [String] {
        core.editorConfirmationLines()
    }

    func openEditorForCurrentContext() {
        AdventureEditorLauncher.present(library: library, initialAdventureID: editorTargetAdventureID())
    }

    private func refresh() {
        state = core.state
        visualTheme = core.visualTheme
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
#endif
