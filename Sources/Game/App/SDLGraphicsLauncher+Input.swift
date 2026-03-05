import CSDL3
import Foundation

extension SDLGraphicsLauncher {
    static func handleKey(
        key: SDL_Keycode,
        session: SharedGameSession,
        showingEditorPrompt: inout Bool
    ) -> Bool {
        switch key {
        case SDLK_T:
            session.cycleVisualTheme()
            return false
        case SDLK_M:
            if session.canOpenEditorFromCurrentMode() {
                showingEditorPrompt = true
            }
            return false
        case SDLK_X:
            session.send(.quit)
            return session.state.shouldQuit
        default:
            break
        }

        guard let command = actionCommand(for: key) else {
            return false
        }
        session.send(command)
        return session.state.shouldQuit
    }

    static func handleEditorKey(
        key: SDL_Keycode,
        editorSession: inout AdventureEditorSession?
    ) -> Bool {
        guard let activeEditor = editorSession else {
            return false
        }

        if activeEditor.showsDocumentPanel {
            switch key {
            case SDLK_UP, SDLK_W:
                activeEditor.movePanelSelection(step: -1)
            case SDLK_DOWN, SDLK_S:
                activeEditor.movePanelSelection(step: 1)
            case SDLK_LEFT, SDLK_A:
                activeEditor.adjustSelectedField(step: -1)
            case SDLK_RIGHT, SDLK_D:
                activeEditor.adjustSelectedField(step: 1)
            case SDLK_E, SDLK_RETURN, SDLK_SPACE:
                activeEditor.activateSelectedField()
            case SDLK_C:
                activeEditor.cycleContentTab()
            case SDLK_Z:
                activeEditor.cycleContentTab(step: -1)
            case SDLK_V:
                activeEditor.cycleContentTab(step: 1)
            case SDLK_P:
                _ = activeEditor.store.validateCurrentPack()
            case SDLK_K:
                activeEditor.store.saveCurrentPack()
            case SDLK_N:
                activeEditor.createBlankAdventure()
            case SDLK_Q, SDLK_ESCAPE, SDLK_M, SDLK_X:
                editorSession = nil
            default:
                return false
            }
            return true
        }

        switch key {
        case SDLK_UP, SDLK_W:
            activeEditor.moveCursor(.up)
        case SDLK_DOWN, SDLK_S:
            activeEditor.moveCursor(.down)
        case SDLK_LEFT, SDLK_A:
            activeEditor.moveCursor(.left)
        case SDLK_RIGHT, SDLK_D:
            activeEditor.moveCursor(.right)
        case SDLK_E, SDLK_RETURN, SDLK_SPACE:
            activeEditor.applyCurrentTool()
        case SDLK_R:
            activeEditor.cycleTool()
        case SDLK_F:
            activeEditor.cycleTool(step: -1)
        case SDLK_C:
            activeEditor.cycleContentTab()
        case SDLK_Z:
            activeEditor.cycleMap(step: -1)
        case SDLK_V:
            activeEditor.cycleMap(step: 1)
        case SDLK_P:
            _ = activeEditor.store.validateCurrentPack()
        case SDLK_K:
            activeEditor.store.saveCurrentPack()
        case SDLK_N:
            activeEditor.createBlankAdventure()
        case SDLK_Q, SDLK_ESCAPE, SDLK_M, SDLK_X:
            editorSession = nil
        default:
            return false
        }

        return true
    }

    static func handleEditorPromptKey(
        key: SDL_Keycode,
        showingEditorPrompt: inout Bool,
        library: GameContentLibrary,
        session: SharedGameSession,
        editorSession: inout AdventureEditorSession?
    ) -> Bool {
        switch key {
        case SDLK_E, SDLK_RETURN, SDLK_SPACE:
            showingEditorPrompt = false
            editorSession = AdventureEditorSession(
                library: library,
                initialAdventureID: session.editorTargetAdventureID()
            )
            return false
        case SDLK_Q, SDLK_ESCAPE, SDLK_M:
            showingEditorPrompt = false
            return false
        case SDLK_X:
            showingEditorPrompt = false
            return false
        default:
            return false
        }
    }

    static func screenshotLabel(
        session: SharedGameSession,
        editorSession: AdventureEditorSession?
    ) -> String {
        if let editorSession {
            let editor = editorSession.sceneSnapshot
            return "editor-\(editor.folderName)-\(editor.currentMapID)-\(editor.selectedContentTab.shortLabel)"
        }

        let state = session.state
        switch state.mode {
        case .title:
            return ScreenshotSupport.defaultGameLabel(for: state)
        case .characterCreation:
            return ScreenshotSupport.defaultGameLabel(for: state)
        case .ending:
            return ScreenshotSupport.defaultGameLabel(for: state)
        default:
            return ScreenshotSupport.defaultGameLabel(for: state)
        }
    }

    static func captureScreenshot(with renderer: OpaquePointer, label: String) -> String {
        guard let surface = SDL_RenderReadPixels(renderer, nil) else {
            return "SHOT FAILED \(sdlError())"
        }
        defer { SDL_DestroySurface(surface) }

        do {
            let url = try ScreenshotSupport.makeScreenshotURL(prefix: "sdl", label: label, fileExtension: "png")
            let saved = url.path.withCString { pointer in
                SDL_SavePNG(surface, pointer)
            }
            if saved {
                return "SHOT SAVED \(url.lastPathComponent.uppercased())"
            }
            return "SHOT FAILED \(sdlError())"
        } catch {
            return "SHOT FAILED \(String(describing: error).uppercased())"
        }
    }

    private static func actionCommand(for key: SDL_Keycode) -> ActionCommand? {
        switch key {
        case SDLK_UP, SDLK_W:
            return .move(.up)
        case SDLK_DOWN, SDLK_S:
            return .move(.down)
        case SDLK_LEFT, SDLK_A:
            return .move(.left)
        case SDLK_RIGHT, SDLK_D:
            return .move(.right)
        case SDLK_SPACE, SDLK_E, SDLK_RETURN:
            return .interact
        case SDLK_I:
            return .openInventory
        case SDLK_R:
            return .dropInventoryItem
        case SDLK_J, SDLK_H:
            return .help
        case SDLK_K:
            return .save
        case SDLK_L:
            return .load
        case SDLK_N:
            return .newGame
        case SDLK_Q, SDLK_ESCAPE:
            return .cancel
        default:
            return nil
        }
    }
}
