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
        soundEngine: any GameSoundPlayback = defaultGraphicsSoundEngine()
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

    func warp(mapID: String?, position: Position, facing: Direction?) throws {
        try core.warp(mapID: mapID, position: position, facing: facing)
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
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: any GameSoundPlayback = defaultGraphicsSoundEngine(),
        automationCommands: [String] = []
    ) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let session = GameSessionController(
            library: library,
            saveRepository: saveRepository,
            playtestAdventureID: playtestAdventureID,
            preferenceStore: preferenceStore,
            soundEngine: soundEngine
        )
        let automationRunner = try automationCommands.isEmpty ? nil : GraphicsAutomationRunner(tokens: automationCommands)
        let delegate = GraphicsAppDelegate(session: session, automationRunner: automationRunner)
        retainedDelegate = delegate
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

@MainActor
final class GraphicsAppDelegate: NSObject, NSApplicationDelegate {
    private let session: GameSessionController
    private let automationRunner: GraphicsAutomationRunner?
    private var window: NSWindow?
    private var automationTimer: Timer?
    private var showDebugLightingOverlay = false

    init(session: GameSessionController, automationRunner: GraphicsAutomationRunner? = nil) {
        self.session = session
        self.automationRunner = automationRunner
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
        startAutomationIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func startAutomationIfNeeded() {
        guard automationRunner != nil else {
            return
        }

        automationTimer?.invalidate()
        automationTimer = Timer.scheduledTimer(
            timeInterval: 0.18,
            target: self,
            selector: #selector(driveAutomationTimer(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func driveAutomationTimer(_ timer: Timer) {
        driveAutomation()
    }

    private func driveAutomation() {
        guard let automationRunner else {
            automationTimer?.invalidate()
            automationTimer = nil
            return
        }

        if automationRunner.isFinished {
            finishAutomation()
            return
        }

        do {
            try automationRunner.step(
                sendCommand: { [session] in session.send($0) },
                warpPlayer: { [session] mapID, position, facing in
                    try session.warp(mapID: mapID, position: position, facing: facing)
                },
                cycleTheme: { [session] in session.cycleVisualTheme() },
                selectTheme: { [session] in session.selectVisualTheme($0) },
                toggleDebugLighting: { [weak self] in
                    self?.showDebugLightingOverlay.toggle()
                    self?.refreshRootView()
                },
                captureScreenshot: { [weak self] label in
                    self?.captureAutomationScreenshot(label: label)
                }
            )
        } catch {
            finishAutomation()
            return
        }

        if automationRunner.isFinished {
            finishAutomation()
        }
    }

    private func captureAutomationScreenshot(label: String?) {
        let resolvedLabel = label ?? ScreenshotSupport.defaultGameLabel(for: session.state)
        _ = try? NativeScreenshotCapture.captureKeyWindow(label: resolvedLabel)
    }

    private func refreshRootView() {
        guard let contentView = window?.contentView as? NSHostingView<GameRootView> else {
            return
        }
        contentView.rootView = GameRootView(
            session: session,
            showDebugLightingOverlay: showDebugLightingOverlay
        )
    }

    private func finishAutomation() {
        automationTimer?.invalidate()
        automationTimer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
