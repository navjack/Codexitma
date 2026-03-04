import AppKit
import Foundation
import SwiftUI

@MainActor
enum AdventureEditorLauncher {
    private static var retainedAppDelegate: StandaloneEditorAppDelegate?
    private static var retainedControllers: [AdventureEditorWindowController] = []

    static func run(library: GameContentLibrary) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = StandaloneEditorAppDelegate()
        retainedAppDelegate = delegate
        app.delegate = delegate
        present(library: library)
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func present(library: GameContentLibrary, initialAdventureID: AdventureID? = nil) {
        let controller = AdventureEditorWindowController(
            library: library,
            initialAdventureID: initialAdventureID
        ) { closedController in
            retainedControllers.removeAll { $0 === closedController }
        }
        retainedControllers.append(controller)
        controller.show()
    }
}

@MainActor
private final class StandaloneEditorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private final class AdventureEditorWindowController: NSObject, NSWindowDelegate {
    private let store: AdventureEditorStore
    private let onClose: (AdventureEditorWindowController) -> Void
    private var window: NSWindow?
    private var hasScheduledClose = false

    init(
        library: GameContentLibrary,
        initialAdventureID: AdventureID?,
        onClose: @escaping (AdventureEditorWindowController) -> Void
    ) {
        self.store = AdventureEditorStore(library: library)
        self.onClose = onClose
        super.init()
        if let initialAdventureID {
            store.selectCatalogAdventure(initialAdventureID)
        }
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard hasScheduledClose == false else {
            return
        }
        hasScheduledClose = true
        window?.delegate = nil
        window = nil
        DispatchQueue.main.async { [self] in
            onClose(self)
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma Adventure Editor"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 1024, height: 680)
        window.delegate = self
        window.center()
        window.contentView = NSHostingView(rootView: AdventureEditorRootView(store: store))
        return window
    }
}
