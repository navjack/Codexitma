import CSDL3
import Foundation

enum GraphicsBackendError: Error, CustomStringConvertible {
    case sdlInitializationFailed(String)
    case sdlWindowCreationFailed(String)
    case sdlRendererCreationFailed(String)

    var description: String {
        switch self {
        case .sdlInitializationFailed(let message):
            return "SDL initialization failed: \(message)"
        case .sdlWindowCreationFailed(let message):
            return "SDL window creation failed: \(message)"
        case .sdlRendererCreationFailed(let message):
            return "SDL renderer creation failed: \(message)"
        }
    }
}

@MainActor
enum SDLGraphicsLauncher {
    private static let windowWidth = 1280
    private static let windowHeight = 800
    private static let resizableWindowFlag: SDL_WindowFlags = 0x20
    private struct DepthFloorProjectionCacheKey: Hashable {
        let width: Int
        let height: Int
        let horizonOffset: Int
        let floorBands: Int
        let facing: Int
        let fieldOfViewMilli: Int
    }

    private struct DepthFloorStripProjection {
        let x0: Int
        let x1: Int
        let xNormalized: Double
        let rayX: Double
        let rayY: Double
    }

    private struct DepthFloorBandProjection {
        let y0: Int
        let y1: Int
        let rowDistance: Double
        let strips: [DepthFloorStripProjection]
    }

    private static var cachedDepthFloorProjection: [DepthFloorProjectionCacheKey: [DepthFloorBandProjection]] = [:]

    static func run(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: any GameSoundPlayback = defaultGraphicsSoundEngine(),
        automationCommands: [String] = []
    ) throws {
        guard SDL_Init(SDL_INIT_VIDEO) else {
            throw GraphicsBackendError.sdlInitializationFailed(sdlError())
        }
        defer { SDL_Quit() }

        let window = SDL_CreateWindow(
            "Codexitma (SDL)",
            Int32(windowWidth),
            Int32(windowHeight),
            resizableWindowFlag
        )
        guard let window else {
            throw GraphicsBackendError.sdlWindowCreationFailed(sdlError())
        }
        defer { SDL_DestroyWindow(window) }

        let renderer = SDL_CreateRenderer(window, nil)
        guard let renderer else {
            throw GraphicsBackendError.sdlRendererCreationFailed(sdlError())
        }
        defer { SDL_DestroyRenderer(renderer) }
        _ = SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

        let session = SharedGameSession(
            library: library,
            saveRepository: saveRepository,
            playtestAdventureID: playtestAdventureID,
            preferenceStore: preferenceStore,
            soundEngine: soundEngine
        )
        let automationRunner = try automationCommands.isEmpty ? nil : GraphicsAutomationRunner(tokens: automationCommands)
        let suppressScreenshotStatusLine = automationRunner != nil
        var running = true
        var showingEditorPrompt = false
        var editorSession: AdventureEditorSession?
        var pendingScreenshotLabel: String?
        var showDebugLightingOverlay = false
        var statusLine: String?
        var statusLineExpiry: UInt64 = 0

        while running {
            let ticks = SDL_GetTicks()
            if statusLine != nil, ticks >= statusLineExpiry {
                statusLine = nil
            }

            var event = SDL_Event()
            while SDL_PollEvent(&event) {
                if event.type == SDL_EVENT_QUIT.rawValue {
                    running = false
                } else if event.type == SDL_EVENT_KEY_DOWN.rawValue {
                    if event.key.repeat {
                        continue
                    }
                    if event.key.key == SDLK_F12 {
                        pendingScreenshotLabel = screenshotLabel(session: session, editorSession: editorSession)
                        continue
                    }
                    if event.key.key == SDLK_F10 {
                        showDebugLightingOverlay.toggle()
                        statusLine = showDebugLightingOverlay ? "DEBUG LIGHT ON" : "DEBUG LIGHT OFF"
                        statusLineExpiry = SDL_GetTicks() + 2200
                        continue
                    }
                    if handleEditorKey(
                        key: event.key.key,
                        editorSession: &editorSession
                    ) {
                        continue
                    }
                    if showingEditorPrompt {
                        if handleEditorPromptKey(
                            key: event.key.key,
                            showingEditorPrompt: &showingEditorPrompt,
                            library: library,
                            session: session,
                            editorSession: &editorSession
                        ) {
                            running = false
                        }
                        continue
                    }
                    if handleKey(
                        key: event.key.key,
                        session: session,
                        showingEditorPrompt: &showingEditorPrompt
                    ) {
                        running = false
                    }
                }
            }

            if session.state.shouldQuit {
                running = false
            }

            if let automationRunner, editorSession == nil, !showingEditorPrompt, pendingScreenshotLabel == nil, running {
                automationRunner.step(
                    sendCommand: { session.send($0) },
                    cycleTheme: { session.cycleVisualTheme() },
                    selectTheme: { session.selectVisualTheme($0) },
                    captureScreenshot: { label in
                        pendingScreenshotLabel = label ?? screenshotLabel(session: session, editorSession: nil)
                    }
                )
            }

            if let editorSession {
                renderAdventureEditor(editorSession, statusLine: statusLine, with: renderer)
            } else {
                let scene = session.sceneSnapshot
                renderScene(
                    scene,
                    editorPromptLines: showingEditorPrompt ? session.editorConfirmationLines() : nil,
                    showDebugLightingOverlay: showDebugLightingOverlay,
                    statusLine: statusLine,
                    with: renderer
                )
            }

            if let label = pendingScreenshotLabel {
                let outcome = captureScreenshot(with: renderer, label: label)
                if !suppressScreenshotStatusLine {
                    statusLine = outcome
                    statusLineExpiry = SDL_GetTicks() + 2600
                }
                pendingScreenshotLabel = nil
            }
            _ = SDL_RenderPresent(renderer)
            if let automationRunner, automationRunner.isFinished, pendingScreenshotLabel == nil {
                running = false
            }
            SDL_Delay(16)
        }
    }

    private static func handleKey(
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

    private static func handleEditorKey(
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

    private static func handleEditorPromptKey(
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

    private static func screenshotLabel(
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

    private static func captureScreenshot(with renderer: OpaquePointer, label: String) -> String {
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

    private static func renderScene(
        _ scene: GraphicsSceneSnapshot,
        editorPromptLines: [String]?,
        showDebugLightingOverlay: Bool,
        statusLine: String?,
        with renderer: OpaquePointer
    ) {
        let viewport = currentViewport(for: renderer)
        fill(renderer, x: 0, y: 0, width: viewport.width, height: viewport.height, color: .background)

        switch scene.mode {
        case .title:
            renderTitleScreen(scene, viewport: viewport, with: renderer)
            if let editorPromptLines {
                renderEditorPrompt(lines: editorPromptLines, viewport: viewport, with: renderer)
            }
            return
        case .characterCreation:
            renderCharacterCreationScreen(scene, viewport: viewport, with: renderer)
            if let editorPromptLines {
                renderEditorPrompt(lines: editorPromptLines, viewport: viewport, with: renderer)
            }
            return
        case .ending:
            renderEndingScreen(scene, viewport: viewport, with: renderer)
            if let editorPromptLines {
                renderEditorPrompt(lines: editorPromptLines, viewport: viewport, with: renderer)
            }
            return
        default:
            break
        }

        let boardFrame = viewport.boardFrame
        let panelFrame = viewport.panelFrame

        if scene.visualTheme == .depth3D, let depth = scene.depth, scene.mode == .exploration {
            renderDepth(
                depth,
                scene: scene,
                frame: boardFrame,
                showDebugLightingOverlay: showDebugLightingOverlay,
                with: renderer
            )
        } else {
            renderBoard(scene, frame: boardFrame, with: renderer)
        }

        fill(renderer, x: panelFrame.x, y: panelFrame.y, width: panelFrame.width, height: panelFrame.height, color: .panel)
        stroke(renderer, frame: panelFrame, color: .gold)

        renderSidebar(scene, frame: panelFrame, with: renderer)
        renderHeader(scene, frame: viewport.headerFrame, statusLine: statusLine, with: renderer)
        if let editorPromptLines {
            renderEditorPrompt(lines: editorPromptLines, viewport: viewport, with: renderer)
        }
    }

    private static func renderAdventureEditor(
        _ editorSession: AdventureEditorSession,
        statusLine: String?,
        with renderer: OpaquePointer
    ) {
        let editor = editorSession.sceneSnapshot
        let viewport = currentViewport(for: renderer)
        fill(renderer, x: 0, y: 0, width: viewport.width, height: viewport.height, color: .editorBackdrop)

        let boardFrame = viewport.boardFrame
        let panelFrame = viewport.panelFrame
        let theme = editorBoardTheme()
        let bannerHeight = max(26, min(40, viewport.contentFrame.height / 8))

        fill(
            renderer,
            x: viewport.contentFrame.x,
            y: viewport.contentFrame.y,
            width: viewport.contentFrame.width,
            height: bannerHeight,
            color: .editorPanel
        )
        stroke(
            renderer,
            frame: SDLRect(
                x: viewport.contentFrame.x,
                y: viewport.contentFrame.y,
                width: viewport.contentFrame.width,
                height: bannerHeight
            ),
            color: .editorAccent
        )

        fill(renderer, x: boardFrame.x, y: boardFrame.y, width: boardFrame.width, height: boardFrame.height, color: theme.frameBackground)
        if viewport.stacked == false {
            fill(renderer, x: boardFrame.x + 6, y: boardFrame.y + 6, width: boardFrame.width, height: boardFrame.height, color: .shadow)
        }
        stroke(renderer, frame: boardFrame, color: theme.outerBorder)
        let contentFrame = boardFrame.insetBy(dx: theme.contentInset, dy: theme.contentInset)
        fill(renderer, x: contentFrame.x, y: contentFrame.y, width: contentFrame.width, height: contentFrame.height, color: theme.boardBackground)

        if editor.showsDocumentPanel {
            renderEditorDocumentBoard(editor, frame: boardFrame, with: renderer)
        } else {
            renderEditorBoard(editor, session: editorSession, frame: boardFrame, theme: theme, with: renderer)
        }

        fill(renderer, x: panelFrame.x, y: panelFrame.y, width: panelFrame.width, height: panelFrame.height, color: .editorPanel)
        stroke(renderer, frame: panelFrame, color: .editorAccent)

        renderEditorSidebar(editor, frame: panelFrame, with: renderer)
        drawText("EDITOR MODE", x: viewport.headerFrame.x + 4, y: viewport.headerFrame.y, color: .editorAccent, renderer: renderer)
        drawText("GAME VIEW PAUSED", x: viewport.headerFrame.x + 120, y: viewport.headerFrame.y, color: .bright, renderer: renderer)
        if let statusLine {
            drawText(String(statusLine.uppercased().prefix(50)), x: viewport.headerFrame.x + max(320, viewport.headerFrame.width / 2), y: viewport.headerFrame.y, color: .gold, renderer: renderer)
        }
        drawText(editor.title.uppercased(), x: viewport.contentFrame.x + 10, y: viewport.contentFrame.y + 8, color: .bright, renderer: renderer)
        drawText(editor.currentMapName.uppercased(), x: viewport.contentFrame.x + min(260, max(120, viewport.contentFrame.width / 3)), y: viewport.contentFrame.y + 8, color: .editorAccent, renderer: renderer)
        drawText("MAP \(editor.currentMapID.uppercased())", x: viewport.contentFrame.x + min(470, max(240, (viewport.contentFrame.width * 2) / 3)), y: viewport.contentFrame.y + 8, color: .dim, renderer: renderer)
    }

    private static func renderTitleScreen(_ scene: GraphicsSceneSnapshot, viewport: SDLViewport, with renderer: OpaquePointer) {
        let frame = viewport.contentFrame
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height, color: .panel)
        stroke(renderer, frame: frame, color: .gold)

        drawText("CODEXITMA", x: frame.x + 18, y: frame.y + 18, color: .gold, renderer: renderer)
        drawText(scene.visualTheme.displayName.uppercased(), x: frame.x + 210, y: frame.y + 18, color: .bright, renderer: renderer)
        drawWrappedText(scene.adventureSummary.uppercased(), x: frame.x + 18, y: frame.y + 42, width: 82, color: .bright, renderer: renderer)

        drawText("ADVENTURES", x: frame.x + 18, y: frame.y + 104, color: .gold, renderer: renderer)
        var y = frame.y + 124
        for (index, entry) in scene.availableAdventures.enumerated() {
            let selected = index == normalizedIndex(scene.selectedAdventureIndex, count: scene.availableAdventures.count)
            let prefix = selected ? ">" : " "
            drawText("\(prefix) \(entry.title.uppercased())", x: frame.x + 18, y: y, color: selected ? .gold : .bright, renderer: renderer)
            y += 14
            drawWrappedText(entry.summary.uppercased(), x: frame.x + 36, y: y, width: 72, color: .dim, renderer: renderer)
            y += 24
        }

        drawText("A/D SELECT  N CREATE  L LOAD", x: frame.x + 18, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
        drawText("M EDIT  T STYLE  F10 DBG  F12 SHOT", x: frame.x + 18, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
        drawText("X QUIT", x: frame.x + 18, y: frame.y + frame.height - 12, color: .bright, renderer: renderer)
    }

    private static func renderCharacterCreationScreen(_ scene: GraphicsSceneSnapshot, viewport: SDLViewport, with renderer: OpaquePointer) {
        let frame = viewport.contentFrame
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height, color: .panel)
        stroke(renderer, frame: frame, color: .gold)

        drawText("CREATE HERO", x: frame.x + 18, y: frame.y + 18, color: .gold, renderer: renderer)
        drawText(scene.adventureTitle.uppercased(), x: frame.x + 190, y: frame.y + 18, color: .bright, renderer: renderer)

        var y = frame.y + 66
        for (index, hero) in scene.heroOptions.enumerated() {
            let selected = index == normalizedIndex(scene.selectedHeroIndex, count: scene.heroOptions.count)
            let prefix = selected ? ">" : " "
            drawText("\(prefix) \(hero.displayName.uppercased())", x: frame.x + 18, y: y, color: selected ? .gold : .bright, renderer: renderer)
            y += 14
            drawWrappedText(hero.summary.uppercased(), x: frame.x + 36, y: y, width: 74, color: .dim, renderer: renderer)
            y += 24
        }

        drawText("TRAITS", x: frame.x + 18, y: frame.y + 238, color: .gold, renderer: renderer)
        drawText(scene.selectedHeroTraitsPrimary.uppercased(), x: frame.x + 18, y: frame.y + 258, color: .bright, renderer: renderer)
        drawText(scene.selectedHeroTraitsSecondary.uppercased(), x: frame.x + 18, y: frame.y + 274, color: .bright, renderer: renderer)

        let skills = scene.selectedHeroSkills.joined(separator: ", ")
        drawText("SKILLS", x: frame.x + 18, y: frame.y + 306, color: .gold, renderer: renderer)
        drawWrappedText(skills.uppercased(), x: frame.x + 18, y: frame.y + 324, width: 78, color: .bright, renderer: renderer)

        drawText("A/D CLASS  E BEGIN  Q BACK", x: frame.x + 18, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
        drawText("M EDIT  T STYLE", x: frame.x + 18, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
    }

    private static func renderEndingScreen(_ scene: GraphicsSceneSnapshot, viewport: SDLViewport, with renderer: OpaquePointer) {
        let frame = viewport.contentFrame.insetBy(dx: 16, dy: 24)
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height, color: .panel)
        stroke(renderer, frame: frame, color: .gold)

        drawText("THE BEACON BURNS AGAIN", x: frame.x + 18, y: frame.y + 22, color: .gold, renderer: renderer)
        var y = frame.y + 62
        for line in scene.messages.suffix(8) {
            drawWrappedText(line.uppercased(), x: frame.x + 18, y: y, width: 78, color: .bright, renderer: renderer)
            y += 30
        }
        drawText("X OR Q TO EXIT", x: frame.x + 18, y: frame.y + frame.height - 28, color: .bright, renderer: renderer)
    }

    private static func renderHeader(
        _ scene: GraphicsSceneSnapshot,
        frame: SDLRect,
        statusLine: String?,
        with renderer: OpaquePointer
    ) {
        drawText(scene.adventureTitle.uppercased(), x: frame.x + 4, y: frame.y, color: .gold, renderer: renderer)
        drawText(scene.visualTheme.displayName.uppercased(), x: frame.x + min(220, max(120, frame.width / 4)), y: frame.y, color: .bright, renderer: renderer)
        drawText(scene.modeLabel, x: frame.x + min(360, max(220, frame.width / 2)), y: frame.y, color: .dim, renderer: renderer)
        if let statusLine {
            drawText(String(statusLine.uppercased().prefix(48)), x: frame.x + max(460, (frame.width * 3) / 5), y: frame.y, color: .gold, renderer: renderer)
        }
    }

    private static func renderSidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        switch scene.mode {
        case .inventory:
            renderInventorySidebar(scene, frame: frame, with: renderer)
            return
        case .shop:
            renderShopSidebar(scene, frame: frame, with: renderer)
            return
        case .dialogue:
            renderDialogueSidebar(scene, frame: frame, with: renderer)
            return
        default:
            break
        }

        renderStatusSidebar(scene, frame: frame, with: renderer)
    }

    private static func renderStatusSidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        var y = frame.y + 10
        let lineHeight = 12

        drawText("MODE \(scene.modeLabel)", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += lineHeight
        drawText("MAP \(scene.currentMapID.uppercased())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("CLASS \(scene.player.heroClass.displayName.uppercased())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("HP \(scene.player.health)/\(scene.player.maxHealth)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("ST \(scene.player.stamina)/\(scene.player.maxStamina)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("ATK \(scene.player.effectiveAttack())  DEF \(scene.player.effectiveDefense())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("LANTERN \(scene.player.effectiveLanternCapacity())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("MARKS \(scene.player.marks)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("FACING \(scene.player.facing.shortLabel)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("BAG \(scene.player.inventory.count)/\(scene.player.inventoryCapacity())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight * 2

        let objective = QuestSystem.objective(for: scene.quests, flow: scene.questFlow)
        drawText("GOAL", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += lineHeight
        for line in wrap(objective.uppercased(), width: 30).prefix(4) {
            drawText(line, x: frame.x + 10, y: y, color: .bright, renderer: renderer)
            y += lineHeight
        }
        y += lineHeight

        drawText("LOG", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += lineHeight
        for line in scene.messages.suffix(10) {
            drawText(line.uppercased(), x: frame.x + 10, y: y, color: .dim, renderer: renderer)
            y += lineHeight
        }
        y += lineHeight

        drawText("WASD MOVE  E ACT  I BAG", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("Q BACK  M EDIT  X QUIT", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("T STYLE  F10 DBG  F12 SHOT", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
    }

    private static func renderDialogueSidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        var y = frame.y + 10
        drawText("DIALOGUE", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += 16
        if let speaker = scene.currentDialogueSpeaker {
            drawText(speaker.uppercased(), x: frame.x + 10, y: y, color: .bright, renderer: renderer)
            y += 16
        }
        for line in scene.currentDialogueLines {
            y = drawWrappedText(line.uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)
            y += 6
        }
        y += 10
        drawText("E OR Q TO CLOSE", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += 14
        drawText("M EDIT  F10 DBG  F12 SHOT", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
    }

    private static func renderInventorySidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        var y = frame.y + 10
        drawText("PACK", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += 16
        drawText("CAP \(scene.player.inventory.count)/\(scene.player.inventoryCapacity())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += 18

        let visibleEntries = visibleInventoryEntries(scene)
        for entry in visibleEntries {
            let prefix = entry.isSelected ? ">" : " "
            let suffix = entry.isEquipped ? " [EQ]" : ""
            drawText("\(prefix) \(entry.name.uppercased())\(suffix)", x: frame.x + 10, y: y, color: entry.isSelected ? .gold : .bright, renderer: renderer)
            y += 14
        }

        if let detail = scene.inventoryDetail {
            y += 10
            drawText("DETAIL", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
            y += 16
            y = drawWrappedText(detail.uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)
        }

        drawText("W/S MOVE  E USE  R DROP", x: frame.x + 10, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
        drawText("Q CLOSE  M EDIT  F10 DBG  F12 SHOT", x: frame.x + 10, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
    }

    private static func renderShopSidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        var y = frame.y + 10
        drawText((scene.shopTitle ?? "MERCHANT").uppercased(), x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += 16
        for line in scene.shopLines {
            y = drawWrappedText(line.uppercased(), x: frame.x + 10, y: y, width: 30, color: .dim, renderer: renderer)
            y += 4
        }
        y += 8

        for offer in visibleShopOffers(scene) {
            let prefix = offer.isSelected ? ">" : " "
            let soldTag = offer.soldOut ? " SOLD" : ""
            drawText("\(prefix) \(offer.label.uppercased()) \(offer.price)M\(soldTag)", x: frame.x + 10, y: y, color: offer.isSelected ? .gold : .bright, renderer: renderer)
            y += 14
            y = drawWrappedText(offer.blurb.uppercased(), x: frame.x + 22, y: y, width: 28, color: .dim, renderer: renderer)
            y += 4
        }

        if let detail = scene.shopDetail {
            y += 8
            drawText("DETAIL", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
            y += 16
            y = drawWrappedText(detail.uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)
        }

        drawText("W/S MOVE  E BUY  Q LEAVE", x: frame.x + 10, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
        drawText("M EDIT  F10 DBG  F12 SHOT", x: frame.x + 10, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
    }

    private static func renderEditorPrompt(
        lines: [String],
        viewport: SDLViewport,
        with renderer: OpaquePointer
    ) {
        fill(renderer, x: 0, y: 0, width: viewport.width, height: viewport.height, color: .overlay)
        let panel = viewport.contentFrame.insetBy(
            dx: max(24, min(160, viewport.contentFrame.width / 5)),
            dy: max(26, min(120, viewport.contentFrame.height / 4))
        )
        fill(renderer, x: panel.x, y: panel.y, width: panel.width, height: panel.height, color: .panel)
        stroke(renderer, frame: panel, color: .gold)

        var y = panel.y + 20
        drawText("OPEN EDITOR?", x: panel.x + 16, y: y, color: .gold, renderer: renderer)
        y += 24
        for line in lines {
            y = drawWrappedText(
                line.uppercased(),
                x: panel.x + 16,
                y: y,
                width: max(28, (panel.width / 8) - 4),
                color: .bright,
                renderer: renderer
            )
            y += 6
        }
        y += 8
        drawText("ARE YOU SURE?", x: panel.x + 16, y: y, color: .gold, renderer: renderer)
        y += 24
        drawText("E OPEN  Q STAY", x: panel.x + 16, y: y, color: .bright, renderer: renderer)
    }

    private static func renderEditorDocumentBoard(
        _ editor: AdventureEditorSceneSnapshot,
        frame: SDLRect,
        with renderer: OpaquePointer
    ) {
        let inset = frame.insetBy(dx: 10, dy: 10)
        fill(renderer, x: inset.x, y: inset.y, width: inset.width, height: inset.height, color: .editorBoard)
        stroke(renderer, frame: inset, color: .editorAccent)

        drawText(editor.panelTitle, x: inset.x + 10, y: inset.y + 10, color: .editorAccent, renderer: renderer)
        drawText(editor.selectedContentTab.shortLabel, x: inset.x + max(160, inset.width / 2), y: inset.y + 10, color: .bright, renderer: renderer)

        let splitX = inset.x + max(180, min(320, inset.width / 2))
        fill(renderer, x: splitX, y: inset.y + 6, width: 2, height: inset.height - 12, color: .editorGrid)

        var y = inset.y + 34
        for (index, field) in editor.panelFields.enumerated() {
            let selected = index == editor.panelSelectionIndex
            let row = SDLRect(x: inset.x + 10, y: y - 2, width: max(120, splitX - inset.x - 20), height: 18)
            if selected {
                fill(renderer, x: row.x, y: row.y, width: row.width, height: row.height, color: .editorAccent.withAlpha(40))
            }
            drawText(field.label, x: inset.x + 12, y: y, color: selected ? .editorAccent : .bright, renderer: renderer)
            drawText(field.value, x: inset.x + 92, y: y, color: field.style == .action ? .editorAccent : .dim, renderer: renderer)
            y += 18
        }

        var previewY = inset.y + 34
        drawText("PREVIEW", x: splitX + 10, y: previewY, color: .editorAccent, renderer: renderer)
        previewY += 18
        for line in editor.previewLines.prefix(16) {
            previewY = drawWrappedText(
                line,
                x: splitX + 10,
                y: previewY,
                width: max(18, ((inset.width - (splitX - inset.x) - 24) / 8)),
                color: .bright,
                renderer: renderer
            )
            previewY += 2
        }
    }

    private static func renderEditorBoard(
        _ editor: AdventureEditorSceneSnapshot,
        session: AdventureEditorSession,
        frame: SDLRect,
        theme: SDLBoardTheme,
        with renderer: OpaquePointer
    ) {
        guard editor.mapLines.isEmpty == false else { return }
        let height = editor.mapLines.count
        let width = editor.mapLines.first?.count ?? 0
        guard width > 0 else { return }

        let contentFrame = frame.insetBy(dx: theme.contentInset, dy: theme.contentInset)
        let cellWidth = max(8, min(contentFrame.width / width, contentFrame.height / height))
        let drawWidth = width * cellWidth
        let drawHeight = height * cellWidth
        let originX = contentFrame.x + ((contentFrame.width - drawWidth) / 2)
        let originY = contentFrame.y + ((contentFrame.height - drawHeight) / 2)

        for (rowIndex, line) in editor.mapLines.enumerated() {
            for (columnIndex, glyph) in Array(line).enumerated() {
                let x = originX + (columnIndex * cellWidth)
                let y = originY + (rowIndex * cellWidth)
                let tile = TileFactory.tile(for: glyph)
                fill(renderer, x: x, y: y, width: cellWidth, height: cellWidth, color: tileColor(for: tile.type, theme: theme))
                if cellWidth >= 10 {
                    stroke(renderer, frame: SDLRect(x: x, y: y, width: cellWidth, height: cellWidth), color: theme.grid)
                }
            }
        }
        for rowIndex in 0..<height {
            let line = Array(editor.mapLines[rowIndex])
            for columnIndex in 0..<min(width, line.count) {
                let position = Position(x: columnIndex, y: rowIndex)
                if let overlay = session.store.overlay(atX: position.x, y: position.y) {
                    let x = originX + (columnIndex * cellWidth)
                    let y = originY + (rowIndex * cellWidth)
                    let inset = max(1, cellWidth / 6)
                    fill(
                        renderer,
                        x: x + inset,
                        y: y + inset,
                        width: max(2, cellWidth - (inset * 2)),
                        height: max(2, cellWidth - (inset * 2)),
                        color: editorOverlayColor(for: overlay.style)
                    )
                    if let glyph = overlay.glyph.first {
                        drawGlyph(
                            glyph,
                            x: x + max(1, (cellWidth / 2) - 2),
                            y: y + max(1, (cellWidth / 2) - 3),
                            color: editorOverlayTextColor(for: overlay.style),
                            scale: max(1, min(2, cellWidth / 8)),
                            renderer: renderer
                        )
                    }
                }
            }
        }

        let cursorX = originX + (editor.cursor.x * cellWidth)
        let cursorY = originY + (editor.cursor.y * cellWidth)
        stroke(renderer, frame: SDLRect(x: cursorX, y: cursorY, width: cellWidth, height: cellWidth), color: .bright)
        let inner = SDLRect(
            x: cursorX + 2,
            y: cursorY + 2,
            width: max(2, cellWidth - 4),
            height: max(2, cellWidth - 4)
        )
        stroke(renderer, frame: inner, color: .gold)
    }

    private static func renderEditorSidebar(
        _ editor: AdventureEditorSceneSnapshot,
        frame: SDLRect,
        with renderer: OpaquePointer
    ) {
        var y = frame.y + 10
        let lineHeight = 12

        drawText("PACK \(editor.folderName.uppercased())", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += lineHeight
        drawText("MAP \(editor.currentMapName.uppercased())", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("CURSOR \(editor.cursor.x),\(editor.cursor.y)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("TOOL \(editor.selectedTool.shortLabel)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("TAB \(editor.selectedContentTab.shortLabel)", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight
        drawText("GLYPH \(String(editor.selectedGlyph))", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
        y += lineHeight * 2

        drawText(editor.showsDocumentPanel ? "PREVIEW" : "SELECTION", x: frame.x + 10, y: y, color: .editorAccent, renderer: renderer)
        y += lineHeight
        let summaryLines = editor.showsDocumentPanel ? editor.previewLines : editor.selectionSummaryLines
        for line in summaryLines.prefix(6) {
            drawText(line.uppercased(), x: frame.x + 10, y: y, color: .bright, renderer: renderer)
            y += lineHeight
        }
        y += lineHeight

        if editor.validationMessages.isEmpty == false {
            drawText("VALIDATION", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
            y += lineHeight
            for line in editor.validationMessages.prefix(4) {
                y = drawWrappedText(line.uppercased(), x: frame.x + 10, y: y, width: 30, color: .dim, renderer: renderer)
                y += 2
            }
            y += lineHeight
        }

        drawText("STATUS", x: frame.x + 10, y: y, color: .editorAccent, renderer: renderer)
        y += lineHeight
        y = drawWrappedText(editor.statusLine.uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)

        if editor.showsDocumentPanel {
            drawText("W/S FIELD  A/D ADJUST", x: frame.x + 10, y: frame.y + frame.height - 56, color: .bright, renderer: renderer)
            drawText("E ACT  C TAB  Z/V TAB", x: frame.x + 10, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
            drawText("K SAVE  P CHECK", x: frame.x + 10, y: frame.y + frame.height - 28, color: .bright, renderer: renderer)
        } else {
            drawText("WASD MOVE  E APPLY", x: frame.x + 10, y: frame.y + frame.height - 56, color: .bright, renderer: renderer)
            drawText("R/F TOOL  C TAB", x: frame.x + 10, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
            drawText("Z/V MAP  K SAVE  P CHECK", x: frame.x + 10, y: frame.y + frame.height - 28, color: .bright, renderer: renderer)
        }
        drawText("N NEW  Q/M/X RETURN  F10 DBG  F12 SHOT", x: frame.x + 10, y: frame.y + frame.height - 14, color: .editorAccent, renderer: renderer)
    }

    private static func renderBoard(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        let board = scene.board
        let theme = boardTheme(for: scene)

        if scene.visualTheme == .gemstone {
            fill(renderer, x: frame.x + 4, y: frame.y + 4, width: frame.width, height: frame.height, color: .shadow)
        }
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height, color: theme.frameBackground)
        stroke(renderer, frame: frame, color: theme.outerBorder)
        let innerInset = theme.innerInset
        if innerInset > 0 {
            stroke(renderer, frame: frame.insetBy(dx: innerInset, dy: innerInset), color: theme.innerBorder)
        }
        let contentFrame = frame.insetBy(dx: theme.contentInset, dy: theme.contentInset)
        fill(renderer, x: contentFrame.x, y: contentFrame.y, width: contentFrame.width, height: contentFrame.height, color: theme.boardBackground)

        guard board.width > 0, board.height > 0 else { return }
        let cellWidth = max(6, min(contentFrame.width / board.width, contentFrame.height / board.height))
        let drawWidth = board.width * cellWidth
        let drawHeight = board.height * cellWidth
        let originX = contentFrame.x + ((contentFrame.width - drawWidth) / 2)
        let originY = contentFrame.y + ((contentFrame.height - drawHeight) / 2)

        for row in board.rows {
            for cell in row {
                let x = originX + (cell.position.x * cellWidth)
                let y = originY + (cell.position.y * cellWidth)
                fill(renderer, x: x, y: y, width: cellWidth, height: cellWidth, color: tileColor(for: cell.tile.type, theme: theme))
                drawTileAccent(
                    for: cell.tile.type,
                    scene: scene,
                    x: x,
                    y: y,
                    cellSize: cellWidth,
                    renderer: renderer
                )
                if cell.feature != .none {
                    let inset = max(1, cellWidth / 6)
                    drawPattern(
                        featurePattern(for: cell.feature),
                        x: x + inset,
                        y: y + inset,
                        width: max(2, cellWidth - (inset * 2)),
                        height: max(2, cellWidth - (inset * 2)),
                        color: featureColor(for: cell.feature),
                        renderer: renderer
                    )
                }
                switch cell.occupant {
                case .none:
                    break
                default:
                    let inset = max(1, cellWidth / 7)
                    drawPattern(
                        occupantPattern(for: cell.occupant),
                        x: x + inset,
                        y: y + inset,
                        width: max(2, cellWidth - (inset * 2)),
                        height: max(2, cellWidth - (inset * 2)),
                        color: occupantColor(for: cell.occupant),
                        renderer: renderer,
                        shadowOffset: cellWidth >= 10 ? max(1, cellWidth / 12) : 0
                    )
                }
                if cellWidth >= 9 {
                    stroke(renderer, frame: SDLRect(x: x, y: y, width: cellWidth, height: cellWidth), color: theme.grid)
                }
            }
        }
    }

    private static func renderDepth(
        _ depth: DepthSceneSnapshot,
        scene: GraphicsSceneSnapshot,
        frame: SDLRect,
        showDebugLightingOverlay: Bool,
        with renderer: OpaquePointer
    ) {
        let depthTheme = boardTheme(for: scene)
        let skyGlow = min(0.22, max(0.04, depth.worldLighting.ambient * 0.45))
        let horizon = frame.y + (frame.height / 2)
        let skyTop = depth.usesSkyBackdrop
            ? blended(.sky, toward: depthTheme.innerBorder, amount: 0.20 + skyGlow)
            : blended(.ceiling, toward: .void, amount: 0.14)
        let skyBottom = depth.usesSkyBackdrop
            ? blended(.ceiling, toward: depthTheme.frameBackground, amount: 0.42)
            : blended(.ceiling, toward: depthTheme.wall, amount: 0.22)
        let skyBands = max(4, frame.height / 42)
        for band in 0..<skyBands {
            let y0 = frame.y + ((frame.height / 2) * band / skyBands)
            let y1 = frame.y + ((frame.height / 2) * (band + 1) / skyBands)
            let ratio = Double(band + 1) / Double(max(1, skyBands))
            let color = blended(skyTop, toward: skyBottom, amount: ratio)
            fill(renderer, x: frame.x, y: y0, width: frame.width, height: max(1, y1 - y0), color: color)
            if band.isMultiple(of: 2) {
                fill(
                    renderer,
                    x: frame.x,
                    y: y0,
                    width: frame.width,
                    height: 1,
                    color: depthTheme.innerBorder.withAlpha(24)
                )
            }
        }

        let floorNear = blended(depthTheme.floor, toward: .bright, amount: 0.09)
        let floorFar = blended(depthTheme.floor, toward: .void, amount: 0.52)
        let floorBands = max(20, frame.height / 14)
        let worldLighting = depth.worldLighting
        let floorLighting = depth.floorLighting
        let floorProjection = depthFloorProjection(
            frame: frame,
            horizon: horizon,
            floorBands: floorBands,
            facing: depth.facing,
            fieldOfView: depth.fieldOfView
        )
        let playerX = Double(scene.player.position.x) + 0.5
        let playerY = Double(scene.player.position.y) + 0.5
        let depthSamples = depth.samples
        let zBuffer = depthSamples.map(\.correctedDistance)

        if !depth.usesSkyBackdrop {
            renderCeilingShadows(
                frame: frame,
                horizon: horizon,
                projection: floorProjection,
                worldLighting: worldLighting,
                playerX: playerX,
                playerY: playerY,
                theme: depthTheme,
                renderer: renderer
            )
        }

        for (band, projection) in floorProjection.enumerated() {
            let y0 = projection.y0
            let y1 = projection.y1
            let t1 = Double(band + 1) / Double(max(1, floorBands))
            let ratio = pow(t1, 0.62)
            let base = blended(floorFar, toward: floorNear, amount: ratio)
            fill(renderer, x: frame.x, y: y0, width: frame.width, height: max(1, y1 - y0), color: base)

            var stripLevels = projection.strips.map { strip in
                let worldX = playerX + (projection.rowDistance * strip.rayX)
                let worldY = playerY + (projection.rowDistance * strip.rayY)
                return worldLighting.level(atWorldX: worldX, y: worldY)
            }
            var stripShadowLevels = projection.strips.map { strip in
                let worldX = playerX + (projection.rowDistance * strip.rayX)
                let worldY = playerY + (projection.rowDistance * strip.rayY)
                return worldLighting.shadowLevel(atWorldX: worldX, y: worldY)
            }
            if stripLevels.count >= 3 {
                var smoothed = stripLevels
                for index in stripLevels.indices {
                    let left = stripLevels[max(0, index - 1)]
                    let center = stripLevels[index]
                    let right = stripLevels[min(stripLevels.count - 1, index + 1)]
                    smoothed[index] = (left * 0.24) + (center * 0.52) + (right * 0.24)
                }
                stripLevels = smoothed
            }
            if stripShadowLevels.count >= 3 {
                var smoothed = stripShadowLevels
                for index in stripShadowLevels.indices {
                    let left = stripShadowLevels[max(0, index - 1)]
                    let center = stripShadowLevels[index]
                    let right = stripShadowLevels[min(stripShadowLevels.count - 1, index + 1)]
                    smoothed[index] = (left * 0.24) + (center * 0.52) + (right * 0.24)
                }
                stripShadowLevels = smoothed
            }

            for (index, strip) in projection.strips.enumerated() {
                let shadow = stripShadowLevels[index]
                let shaded = max(floorLighting.ambient * 0.10, stripLevels[index] - (shadow * 0.74))
                let lift = max(0.0, shaded - floorLighting.ambient)
                let dim = max(max(0.0, floorLighting.ambient - shaded), shadow * 0.40)

                if lift <= 0.01, dim <= 0.01 {
                    continue
                }

                let width = max(1, strip.x1 - strip.x0)
                if lift > 0.01 {
                    let alpha = UInt8(max(0, min(170, Int((0.05 + (lift * 0.58)) * 255.0))))
                    let glow = blended(depthTheme.innerBorder, toward: .bright, amount: 0.34)
                    fill(renderer, x: strip.x0, y: y0, width: width, height: max(1, y1 - y0), color: glow.withAlpha(alpha))
                }
                if dim > 0.01 {
                    let alpha = UInt8(max(0, min(110, Int((0.04 + (dim * 0.34)) * 255.0))))
                    fill(renderer, x: strip.x0, y: y0, width: width, height: max(1, y1 - y0), color: .void.withAlpha(alpha))
                }
                if shadow > 0.01 {
                    let alpha = UInt8(max(0, min(130, Int((shadow * 0.28) * 255.0))))
                    fill(renderer, x: strip.x0, y: y0, width: width, height: max(1, y1 - y0), color: .void.withAlpha(alpha))
                }
            }
            if band.isMultiple(of: 2) {
                fill(renderer, x: frame.x, y: y0, width: frame.width, height: 1, color: depthTheme.innerBorder.withAlpha(10))
            }
        }

        let centerX = frame.x + (frame.width / 2)
        let bottomY = frame.y + frame.height - 1
        for step in -4...4 {
            let normalized = Double(step) / 4.0
            let endX = centerX + Int(Double(frame.width) * normalized * 0.46)
            drawLine(
                renderer,
                fromX: centerX,
                fromY: horizon,
                toX: endX,
                toY: bottomY,
                color: depthTheme.innerBorder.withAlpha(20)
            )
        }
        fill(renderer, x: frame.x, y: horizon, width: frame.width, height: 1, color: depthTheme.innerBorder.withAlpha(36))
        stroke(renderer, frame: frame, color: .gold)

        guard !depthSamples.isEmpty else { return }
        let columnWidth = max(1, frame.width / depthSamples.count)
        let fogColor = depth.usesSkyBackdrop
            ? blended(depthTheme.frameBackground, toward: .sky, amount: 0.35)
            : blended(.ceiling, toward: .void, amount: 0.40)

        for sample in depthSamples where sample.didHit {
            let distance = max(0.14, sample.correctedDistance)
            let wallHeight = min(Double(frame.height) * 0.92, (Double(frame.height) * 0.82) / distance)
            let top = Int(Double(horizon) - (wallHeight * 0.5))
            let height = max(1, Int(wallHeight))
            let x = frame.x + (sample.column * columnWidth)
            let distanceRatio = sample.correctedDistance / depth.maxDistance
            let axisShade = sample.hitAxis == .vertical ? 0.78 : 0.92
            let lightShade = max(0.18, min(1.0, sample.lightLevel))
            let shadowShade = max(0.0, min(1.0, sample.shadowLevel))
            let effectiveShade = max(0.14, lightShade * (1.0 - (shadowShade * 0.78)))
            var color = shaded(
                tileColor(for: sample.hitTile.type, theme: depthTheme),
                intensity: max(0.22, 1.0 - (distanceRatio * 0.72)) * axisShade * effectiveShade
            )
            let fogAmount = max(0.0, min(0.78, (distanceRatio - 0.34) * 1.35))
            color = blended(color, toward: fogColor, amount: fogAmount)
            fill(renderer, x: x, y: top, width: max(1, columnWidth + 1), height: height, color: color)

            if sample.column.isMultiple(of: 3) {
                fill(
                    renderer,
                    x: x,
                    y: top,
                    width: max(1, (columnWidth + 1) / 3),
                    height: height,
                    color: .void.withAlpha(24)
                )
            }
            if effectiveShade < 0.65 {
                let darkness = UInt8(max(0, min(170, Int((0.65 - effectiveShade) * 255.0))))
                fill(renderer, x: x, y: top, width: max(1, columnWidth + 1), height: height, color: .void.withAlpha(darkness))
            }
            if shadowShade > 0.01 {
                let shadowAlpha = UInt8(max(0, min(130, Int((shadowShade * 0.26) * 255.0))))
                fill(renderer, x: x, y: top, width: max(1, columnWidth + 1), height: height, color: .void.withAlpha(shadowAlpha))
            }
            fill(
                renderer,
                x: x,
                y: top,
                width: max(1, columnWidth + 1),
                height: 1,
                color: blended(color, toward: .bright, amount: 0.18).withAlpha(110)
            )
        }

        for billboard in depth.billboards.sorted(by: { $0.distance > $1.distance }) {
            let screenCenter = Int((((billboard.angleOffset / depth.fieldOfView) + 0.5) * Double(frame.width))) + frame.x
            let projectedHeight = min(
                Double(frame.height) * 0.88,
                (Double(frame.height) * billboard.scale) / max(0.16, billboard.distance)
            )
            let projectedWidth = max(10.0, projectedHeight * 0.52 * billboard.widthScale)
            let left = Int(Double(screenCenter) - (projectedWidth / 2.0))
            let width = max(2, Int(projectedWidth))
            let top = Int(Double(horizon) - (projectedHeight * 0.5))
            let height = max(2, Int(projectedHeight))
            let startSample = max(0, (left - frame.x) / columnWidth)
            let endSample = min(depthSamples.count - 1, (left - frame.x + width - 1) / columnWidth)
            if startSample <= endSample {
                var visible = false
                for sampleIndex in startSample...endSample where billboard.distance <= (zBuffer[sampleIndex] + 0.06) {
                    visible = true
                    break
                }
                if !visible {
                    continue
                }
            }

            let distanceRatio = billboard.distance / depth.maxDistance
            let lightShade = max(0.18, min(1.0, billboard.lightLevel))
            let distanceShade = max(0.24, 1.0 - (distanceRatio * 0.72))
            let fogAmount = max(0.0, min(0.70, (distanceRatio - 0.42) * 1.42))
            let spriteBase = shaded(
                billboardColor(for: billboard.kind, theme: depthTheme),
                intensity: distanceShade * lightShade
            )
            let spriteColor = blended(spriteBase, toward: fogColor, amount: fogAmount * 0.82)
            let shadowAlpha = UInt8(max(24, min(136, Int((0.42 - (lightShade * 0.22)) * 255.0))))
            let shadowY = min(frame.y + frame.height - 2, top + height - max(2, height / 12))
            fill(
                renderer,
                x: left + max(1, width / 8),
                y: shadowY,
                width: max(2, (width * 3) / 4),
                height: max(2, height / 10),
                color: .shadow.withAlpha(shadowAlpha)
            )
            drawPattern(
                billboardPattern(for: billboard.kind),
                x: left,
                y: top,
                width: width,
                height: height,
                color: spriteColor,
                renderer: renderer,
                shadowOffset: width >= 14 ? 2 : 1
            )
            if fogAmount > 0.06 {
                let fogAlpha = UInt8(max(8, min(132, Int(fogAmount * 168.0))))
                fill(
                    renderer,
                    x: left,
                    y: top,
                    width: width,
                    height: height,
                    color: fogColor.withAlpha(fogAlpha)
                )
            }
        }

        let cx = frame.x + (frame.width / 2)
        let cy = frame.y + (frame.height / 2)
        fill(renderer, x: cx - 10, y: cy, width: 20, height: 2, color: .bright)
        fill(renderer, x: cx, y: cy - 10, width: 2, height: 20, color: .bright)
        drawText("VIEW \(scene.player.facing.shortLabel)", x: frame.x + 10, y: frame.y + 10, color: .gold, renderer: renderer)
        drawText("RANGE \(Int(depth.maxDistance.rounded()))", x: frame.x + 10, y: frame.y + 24, color: .bright, renderer: renderer)
        if showDebugLightingOverlay {
            renderDepthDebugOverlay(depth: depth, scene: scene, frame: frame, with: renderer)
        }
    }

    private static func renderCeilingShadows(
        frame: SDLRect,
        horizon: Int,
        projection: [DepthFloorBandProjection],
        worldLighting: DepthWorldLightingSnapshot,
        playerX: Double,
        playerY: Double,
        theme: SDLBoardTheme,
        renderer: OpaquePointer
    ) {
        for band in projection {
            let mirroredY0 = horizon - (band.y1 - horizon)
            let mirroredY1 = horizon - (band.y0 - horizon)
            let y0 = max(frame.y, mirroredY0)
            let y1 = min(horizon, mirroredY1)
            if y1 <= y0 {
                continue
            }

            var stripLevels = band.strips.map { strip in
                let worldX = playerX + (band.rowDistance * strip.rayX)
                let worldY = playerY + (band.rowDistance * strip.rayY)
                return worldLighting.effectiveLevel(
                    atWorldX: worldX,
                    y: worldY,
                    shadowWeight: 0.72,
                    minimumAmbientFactor: 0.14
                )
            }
            var stripShadowLevels = band.strips.map { strip in
                let worldX = playerX + (band.rowDistance * strip.rayX)
                let worldY = playerY + (band.rowDistance * strip.rayY)
                return worldLighting.shadowLevel(atWorldX: worldX, y: worldY)
            }

            if stripLevels.count >= 3 {
                var smoothed = stripLevels
                for index in stripLevels.indices {
                    let left = stripLevels[max(0, index - 1)]
                    let center = stripLevels[index]
                    let right = stripLevels[min(stripLevels.count - 1, index + 1)]
                    smoothed[index] = (left * 0.24) + (center * 0.52) + (right * 0.24)
                }
                stripLevels = smoothed
            }
            if stripShadowLevels.count >= 3 {
                var smoothed = stripShadowLevels
                for index in stripShadowLevels.indices {
                    let left = stripShadowLevels[max(0, index - 1)]
                    let center = stripShadowLevels[index]
                    let right = stripShadowLevels[min(stripShadowLevels.count - 1, index + 1)]
                    smoothed[index] = (left * 0.24) + (center * 0.52) + (right * 0.24)
                }
                stripShadowLevels = smoothed
            }

            for (index, strip) in band.strips.enumerated() {
                let width = max(1, strip.x1 - strip.x0)
                let level = stripLevels[index]
                let shadow = stripShadowLevels[index]
                let dim = max(max(0.0, worldLighting.ambient - level), shadow * 0.46)
                let lift = max(0.0, level - worldLighting.ambient)

                if dim > 0.01 {
                    let alpha = UInt8(max(0, min(170, Int((0.04 + (dim * 0.46)) * 255.0))))
                    fill(renderer, x: strip.x0, y: y0, width: width, height: max(1, y1 - y0), color: .void.withAlpha(alpha))
                }
                if shadow > 0.01 {
                    let alpha = UInt8(max(0, min(145, Int((shadow * 0.30) * 255.0))))
                    fill(renderer, x: strip.x0, y: y0, width: width, height: max(1, y1 - y0), color: .void.withAlpha(alpha))
                }
                if lift > 0.01 {
                    let alpha = UInt8(max(0, min(90, Int((0.02 + (lift * 0.22)) * 255.0))))
                    fill(
                        renderer,
                        x: strip.x0,
                        y: y0,
                        width: width,
                        height: max(1, y1 - y0),
                        color: theme.innerBorder.withAlpha(alpha)
                    )
                }
            }
        }
    }

    private static func renderDepthDebugOverlay(
        depth: DepthSceneSnapshot,
        scene: GraphicsSceneSnapshot,
        frame: SDLRect,
        with renderer: OpaquePointer
    ) {
        let panelWidth = min(210, max(148, frame.width / 3))
        let panelHeight = min(170, max(124, frame.height / 2))
        let panel = SDLRect(
            x: frame.x + frame.width - panelWidth - 8,
            y: frame.y + 8,
            width: panelWidth,
            height: panelHeight
        )
        fill(renderer, x: panel.x, y: panel.y, width: panel.width, height: panel.height, color: .overlay)
        stroke(renderer, frame: panel, color: .gold)

        let levels = depth.tileLighting.values.flatMap { $0 }
        let minimum = levels.min() ?? depth.tileLighting.ambient
        let maximum = levels.max() ?? depth.tileLighting.ambient
        let average = levels.isEmpty ? depth.tileLighting.ambient : (levels.reduce(0, +) / Double(levels.count))

        drawText("DEBUG LIGHT", x: panel.x + 8, y: panel.y + 8, color: .gold, renderer: renderer)
        drawText("A \(lightString(depth.tileLighting.ambient))", x: panel.x + 8, y: panel.y + 22, color: .bright, renderer: renderer)
        drawText("N \(lightString(minimum)) X \(lightString(maximum))", x: panel.x + 8, y: panel.y + 36, color: .bright, renderer: renderer)
        drawText("M \(lightString(average))", x: panel.x + 8, y: panel.y + 50, color: .bright, renderer: renderer)
        drawText("P \(scene.player.position.x),\(scene.player.position.y) \(scene.player.facing.shortLabel)", x: panel.x + 8, y: panel.y + 64, color: .dim, renderer: renderer)

        let mapArea = SDLRect(
            x: panel.x + 8,
            y: panel.y + 80,
            width: panel.width - 16,
            height: panel.height - 88
        )
        fill(renderer, x: mapArea.x, y: mapArea.y, width: mapArea.width, height: mapArea.height, color: .void.withAlpha(130))
        stroke(renderer, frame: mapArea, color: .bright.withAlpha(80))

        guard scene.board.width > 0, scene.board.height > 0 else { return }
        let cellSize = max(2, min(mapArea.width / scene.board.width, mapArea.height / scene.board.height))
        let drawWidth = scene.board.width * cellSize
        let drawHeight = scene.board.height * cellSize
        let originX = mapArea.x + ((mapArea.width - drawWidth) / 2)
        let originY = mapArea.y + ((mapArea.height - drawHeight) / 2)

        for row in scene.board.rows {
            for cell in row {
                let x = originX + (cell.position.x * cellSize)
                let y = originY + (cell.position.y * cellSize)
                let level = depth.tileLighting.level(at: cell.position)
                let normalized = max(0.0, min(1.0, (level - depth.tileLighting.ambient) * 1.8 + 0.26))
                var color = SDLColor(
                    r: UInt8(max(0, min(255, Int(20 + (normalized * 210))))),
                    g: UInt8(max(0, min(255, Int(18 + (normalized * 176))))),
                    b: UInt8(max(0, min(255, Int(22 + (normalized * 140))))),
                    a: 255
                )
                if !cell.tile.walkable {
                    color = SDLColor(
                        r: UInt8(max(0, min(255, Int(18 + (normalized * 90))))),
                        g: UInt8(max(0, min(255, Int(18 + (normalized * 74))))),
                        b: UInt8(max(0, min(255, Int(20 + (normalized * 60))))),
                        a: 255
                    )
                }
                fill(renderer, x: x, y: y, width: cellSize, height: cellSize, color: color)

                if cell.feature == .torchFloor || cell.feature == .torchWall {
                    let dot = max(1, cellSize / 2)
                    fill(
                        renderer,
                        x: x + max(0, (cellSize - dot) / 2),
                        y: y + max(0, (cellSize - dot) / 2),
                        width: dot,
                        height: dot,
                        color: .gold
                    )
                }
                if !cell.tile.walkable {
                    stroke(renderer, frame: SDLRect(x: x, y: y, width: cellSize, height: cellSize), color: .shadow.withAlpha(150))
                }
            }
        }

        let playerX = originX + (scene.player.position.x * cellSize)
        let playerY = originY + (scene.player.position.y * cellSize)
        let inset = max(0, cellSize / 4)
        fill(
            renderer,
            x: playerX + inset,
            y: playerY + inset,
            width: max(1, cellSize - (inset * 2)),
            height: max(1, cellSize - (inset * 2)),
            color: .water
        )
    }

    private static func lightString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func depthFloorProjection(
        frame: SDLRect,
        horizon: Int,
        floorBands: Int,
        facing: Direction,
        fieldOfView: Double
    ) -> [DepthFloorBandProjection] {
        let key = DepthFloorProjectionCacheKey(
            width: frame.width,
            height: frame.height,
            horizonOffset: horizon - frame.y,
            floorBands: floorBands,
            facing: facingKey(for: facing),
            fieldOfViewMilli: Int((fieldOfView * 1000.0).rounded())
        )
        if let cached = cachedDepthFloorProjection[key] {
            return cached
        }

        let forward = facingUnitVector(for: facing)
        let right = rightUnitVector(for: facing)
        let planeScale = tan(fieldOfView * 0.5)
        let leftRay = (
            x: forward.x - (right.x * planeScale),
            y: forward.y - (right.y * planeScale)
        )
        let rightRay = (
            x: forward.x + (right.x * planeScale),
            y: forward.y + (right.y * planeScale)
        )
        let posZ = Double(frame.height) * 0.50
        let totalHeight = Double(frame.height - (horizon - frame.y))
        var result: [DepthFloorBandProjection] = []
        result.reserveCapacity(max(1, floorBands))

        for band in 0..<max(1, floorBands) {
            let t0 = Double(band) / Double(max(1, floorBands))
            let t1 = Double(band + 1) / Double(max(1, floorBands))
            let y0 = horizon + Int(totalHeight * pow(t0, 1.58))
            let y1 = horizon + Int(totalHeight * pow(t1, 1.58))
            let bandNorm = (Double(band) + 0.5) / Double(max(1, floorBands))
            let rowScreenY = max(Double(horizon + 1), Double(y0 + y1) * 0.5)
            let rowDepth = max(1.0, rowScreenY - Double(horizon))
            let normalizedScreenDepth = max(
                0.0,
                min(1.0, (rowScreenY - Double(horizon)) / max(1.0, Double(frame.height - (horizon - frame.y))))
            )
            let perspectiveWarp = 0.72 + (pow(1.0 - normalizedScreenDepth, 1.55) * 0.65)
            let rowDistance = (posZ / rowDepth) * perspectiveWarp
            let stripScale = 0.78 + (pow(1.0 - bandNorm, 1.2) * 0.72)
            let stripCount = max(64, Int((Double(frame.width) * 0.52) * stripScale))
            var strips: [DepthFloorStripProjection] = []
            strips.reserveCapacity(stripCount)

            for strip in 0..<stripCount {
                let xNormalized = (Double(strip) + 0.5) / Double(stripCount)
                let rayX = leftRay.x + ((rightRay.x - leftRay.x) * xNormalized)
                let rayY = leftRay.y + ((rightRay.y - leftRay.y) * xNormalized)
                let x0 = frame.x + Int((Double(strip) / Double(stripCount)) * Double(frame.width))
                let x1 = frame.x + Int((Double(strip + 1) / Double(stripCount)) * Double(frame.width))
                strips.append(
                    DepthFloorStripProjection(
                        x0: x0,
                        x1: x1,
                        xNormalized: xNormalized,
                        rayX: rayX,
                        rayY: rayY
                    )
                )
            }

            result.append(
                DepthFloorBandProjection(
                    y0: y0,
                    y1: y1,
                    rowDistance: rowDistance,
                    strips: strips
                )
            )
        }

        cachedDepthFloorProjection[key] = result
        if cachedDepthFloorProjection.count > 24 {
            cachedDepthFloorProjection.removeAll(keepingCapacity: true)
            cachedDepthFloorProjection[key] = result
        }
        return result
    }

    private static func facingUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        switch direction {
        case .up:
            return (0, -1)
        case .down:
            return (0, 1)
        case .left:
            return (-1, 0)
        case .right:
            return (1, 0)
        }
    }

    private static func rightUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        switch direction {
        case .up:
            return (1, 0)
        case .down:
            return (-1, 0)
        case .left:
            return (0, -1)
        case .right:
            return (0, 1)
        }
    }

    private static func facingKey(for direction: Direction) -> Int {
        switch direction {
        case .up:
            return 0
        case .right:
            return 1
        case .down:
            return 2
        case .left:
            return 3
        }
    }

    private static func tileColor(for type: TileType, theme: SDLBoardTheme) -> SDLColor {
        switch type {
        case .floor: return theme.floor
        case .wall: return theme.wall
        case .water: return theme.water
        case .brush: return theme.brush
        case .doorLocked: return theme.doorLocked
        case .doorOpen: return theme.doorOpen
        case .shrine: return theme.shrine
        case .stairs: return theme.stairs
        case .beacon: return theme.beacon
        }
    }

    private static func featureColor(for feature: MapFeature) -> SDLColor {
        if let color = GraphicsAssetCatalog.featureSprite(for: feature.debugName)?.color {
            return SDLColor(color)
        }
        switch feature {
        case .none: return .bright
        case .chest: return .gold
        case .bed: return .bright
        case .plateUp: return .violet
        case .plateDown: return .dim
        case .switchIdle: return .blue
        case .switchLit: return .gold
        case .torchFloor: return .gold
        case .torchWall: return .doorOpen
        case .shrine: return .violet
        case .beacon: return .beacon
        case .gate: return .doorLocked
        }
    }

    private static func occupantColor(for occupant: MapOccupant) -> SDLColor {
        switch occupant {
        case .none: return .bright
        case .player:
            if let color = GraphicsAssetCatalog.occupantSprite(for: "player")?.color {
                return SDLColor(color)
            }
            return .bright
        case .npc(let id):
            if let color = GraphicsAssetCatalog.npcSprite(for: id)?.color {
                return SDLColor(color)
            }
            if let color = GraphicsAssetCatalog.occupantSprite(for: id)?.color {
                return SDLColor(color)
            }
            return .blue
        case .enemy(let id):
            if let color = GraphicsAssetCatalog.enemySprite(for: id)?.color {
                return SDLColor(color)
            }
            if let color = GraphicsAssetCatalog.occupantSprite(for: id)?.color {
                return SDLColor(color)
            }
            return .green
        case .boss(let id):
            if let color = GraphicsAssetCatalog.occupantSprite(for: "boss")?.color {
                return SDLColor(color)
            }
            if let color = GraphicsAssetCatalog.enemySprite(for: id)?.color {
                return SDLColor(color)
            }
            return .violet
        }
    }

    private static func color(for ansi: ANSIColor) -> SDLColor {
        switch ansi {
        case .black:
            return .void
        case .red:
            return SDLColor(r: 220, g: 56, b: 40, a: 255)
        case .green:
            return .green
        case .yellow:
            return .gold
        case .blue:
            return .blue
        case .magenta:
            return .violet
        case .cyan:
            return SDLColor(r: 52, g: 196, b: 214, a: 255)
        case .white:
            return .bright
        case .brightBlack:
            return .dim
        case .reset:
            return .bright
        }
    }

    private static func color(for kind: InteractableKind) -> SDLColor {
        switch kind {
        case .npc:
            return .gold
        case .shrine:
            return .violet
        case .chest:
            return .doorLocked
        case .bed:
            return .wallShade
        case .gate:
            return .doorLocked
        case .beacon:
            return .beacon
        case .plate:
            return .bright
        case .switchRune:
            return .blue
        case .torchFloor:
            return .gold
        case .torchWall:
            return .doorOpen
        }
    }

    private static func editorOverlayColor(for style: EditorCanvasOverlayStyle) -> SDLColor {
        switch style {
        case .ansi(let ansi):
            return color(for: ansi)
        case .interactable(let kind):
            return color(for: kind)
        case .portal:
            return .gold
        case .spawn:
            return .bright
        }
    }

    private static func editorOverlayTextColor(for style: EditorCanvasOverlayStyle) -> SDLColor {
        switch style {
        case .ansi(.black), .ansi(.blue), .ansi(.magenta), .ansi(.brightBlack):
            return .bright
        case .ansi, .interactable, .portal, .spawn:
            return .background
        }
    }

    private static func billboardColor(for kind: DepthBillboardKind, theme: SDLBoardTheme) -> SDLColor {
        switch kind {
        case .npc(let id):
            return occupantColor(for: .npc(id))
        case .enemy(let id):
            return occupantColor(for: .enemy(id))
        case .boss(let id):
            return occupantColor(for: .boss(id))
        case .feature(let feature):
            return featureColor(for: feature)
        case .tile(let tileType):
            return tileColor(for: tileType, theme: theme)
        }
    }

    private static func drawTileAccent(
        for type: TileType,
        scene: GraphicsSceneSnapshot,
        x: Int,
        y: Int,
        cellSize: Int,
        renderer: OpaquePointer
    ) {
        switch type {
        case .floor:
            drawFloorAccent(scene: scene, x: x, y: y, cellSize: cellSize, renderer: renderer)
        case .wall:
            let topBand = max(1, cellSize / 5)
            fill(renderer, x: x, y: y, width: cellSize, height: topBand, color: .wallShade)
            if scene.visualTheme == .gemstone {
                fill(renderer, x: x, y: y + (cellSize / 2), width: cellSize, height: max(1, cellSize / 6), color: .bright.withAlpha(55))
            }
        case .water:
            let stripeHeight = max(1, cellSize / 7)
            fill(renderer, x: x + 1, y: y + stripeHeight, width: max(1, cellSize - 2), height: stripeHeight, color: .bright.withAlpha(110))
            fill(renderer, x: x + 2, y: y + (stripeHeight * 3), width: max(1, cellSize - 4), height: stripeHeight, color: .bright.withAlpha(80))
        case .brush:
            let bladeWidth = max(1, cellSize / 6)
            fill(renderer, x: x + bladeWidth, y: y + (cellSize / 3), width: bladeWidth, height: max(1, cellSize / 2), color: .wallShade)
            fill(renderer, x: x + (bladeWidth * 3), y: y + (cellSize / 5), width: bladeWidth, height: max(1, (cellSize * 3) / 5), color: .bright.withAlpha(80))
        case .doorLocked, .doorOpen:
            let width = max(2, cellSize / 3)
            fill(renderer, x: x + ((cellSize - width) / 2), y: y + max(1, cellSize / 8), width: width, height: max(2, (cellSize * 3) / 4), color: .wallShade)
        case .shrine, .beacon:
            let width = max(2, cellSize / 3)
            let height = max(2, cellSize / 2)
            fill(renderer, x: x + ((cellSize - width) / 2), y: y + ((cellSize - height) / 2), width: width, height: height, color: .bright.withAlpha(70))
        case .stairs:
            let stepHeight = max(1, cellSize / 8)
            fill(renderer, x: x + (cellSize / 4), y: y + (cellSize / 3), width: max(2, cellSize / 3), height: stepHeight, color: .wallShade)
            fill(renderer, x: x + (cellSize / 3), y: y + (cellSize / 2), width: max(2, cellSize / 2), height: stepHeight, color: .wallShade)
        }
    }

    private static func drawFloorAccent(
        scene: GraphicsSceneSnapshot,
        x: Int,
        y: Int,
        cellSize: Int,
        renderer: OpaquePointer
    ) {
        let pattern = floorPattern(for: scene.currentMapID)
        let accent: SDLColor = scene.visualTheme == .gemstone
            ? SDLColor.bright.withAlpha(55)
            : SDLColor.wallShade.withAlpha(95)
        let dark = SDLColor.wallShade

        switch scene.visualTheme {
        case .ultima:
            if cellSize >= 8 {
                fill(renderer, x: x + (cellSize / 3), y: y + (cellSize / 3), width: max(1, cellSize / 5), height: max(1, cellSize / 5), color: accent)
            }
        case .gemstone, .depth3D:
            switch pattern {
            case .brick:
                let band = max(1, cellSize / 7)
                fill(renderer, x: x, y: y + band, width: cellSize, height: band, color: accent)
                fill(renderer, x: x + (cellSize / 3), y: y + (band * 3), width: max(1, cellSize / 3), height: band, color: accent)
            case .speckle:
                fill(renderer, x: x + (cellSize / 4), y: y + (cellSize / 4), width: max(1, cellSize / 7), height: max(1, cellSize / 7), color: accent)
                fill(renderer, x: x + (cellSize / 2), y: y + (cellSize / 2), width: max(1, cellSize / 7), height: max(1, cellSize / 7), color: dark)
            case .weave:
                fill(renderer, x: x + (cellSize / 3), y: y, width: max(1, cellSize / 8), height: cellSize, color: accent)
                fill(renderer, x: x, y: y + (cellSize / 2), width: cellSize, height: max(1, cellSize / 8), color: accent)
            case .hash:
                let step = max(1, cellSize / 4)
                fill(renderer, x: x + step, y: y + step, width: max(1, cellSize / 8), height: max(1, cellSize / 2), color: accent)
                fill(renderer, x: x + (step * 2), y: y + max(1, step / 2), width: max(1, cellSize / 8), height: max(1, cellSize / 2), color: dark)
            case .mire:
                let band = max(1, cellSize / 8)
                fill(renderer, x: x + 1, y: y + (cellSize / 3), width: max(1, cellSize - 2), height: band, color: dark.withAlpha(120))
                fill(renderer, x: x + (cellSize / 4), y: y + (cellSize / 2), width: max(1, cellSize / 2), height: band, color: accent)
            case .circuit:
                let line = max(1, cellSize / 8)
                fill(renderer, x: x + (cellSize / 2), y: y + line, width: line, height: max(1, cellSize - (line * 2)), color: accent)
                fill(renderer, x: x + line, y: y + (cellSize / 2), width: max(1, cellSize - (line * 2)), height: line, color: accent)
            }
        }
    }

    private static func featurePattern(for feature: MapFeature) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.featureSprite(for: feature.debugName)?.pattern?.rows {
            return pattern
        }
        switch feature {
        case .none:
            return [[1]]
        case .chest:
            return [
                [0, 1, 1, 0],
                [1, 1, 1, 1],
                [1, 0, 0, 1]
            ]
        case .bed:
            return [
                [1, 1, 1, 1],
                [1, 0, 0, 0]
            ]
        case .plateUp:
            return [
                [1, 1, 1],
                [1, 1, 1]
            ]
        case .plateDown:
            return [
                [1, 1, 1]
            ]
        case .switchIdle, .switchLit:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0]
            ]
        case .torchFloor:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0],
                [0, 1, 0]
            ]
        case .torchWall:
            return [
                [1, 1, 1],
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0]
            ]
        case .shrine:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1],
                [0, 1, 0]
            ]
        case .beacon:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 1, 1]
            ]
        case .gate:
            return [
                [1, 0, 1],
                [1, 0, 1],
                [1, 1, 1]
            ]
        }
    }

    private static func occupantPattern(for occupant: MapOccupant) -> [[Int]] {
        switch occupant {
        case .none:
            return [[1]]
        case .player:
            if let pattern = GraphicsAssetCatalog.occupantSprite(for: "player")?.pattern?.rows {
                return pattern
            }
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1]
            ]
        case .npc(let id):
            if let pattern = GraphicsAssetCatalog.occupantSprite(for: id)?.pattern?.rows {
                return pattern
            }
            return npcPattern(for: id)
        case .enemy(let id):
            if let pattern = GraphicsAssetCatalog.occupantSprite(for: id)?.pattern?.rows {
                return pattern
            }
            return enemyPattern(for: id)
        case .boss(let id):
            if let pattern = GraphicsAssetCatalog.occupantSprite(for: "boss")?.pattern?.rows {
                return pattern
            }
            if let pattern = GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows {
                return pattern
            }
            return [
                [1, 0, 1],
                [1, 1, 1],
                [1, 1, 1]
            ]
        }
    }

    private static func billboardPattern(for kind: DepthBillboardKind) -> [[Int]] {
        switch kind {
        case .npc(let id):
            return npcPattern(for: id)
        case .enemy(let id):
            return enemyPattern(for: id)
        case .boss(let id):
            return occupantPattern(for: .boss(id))
        case .feature(let feature):
            return featurePattern(for: feature)
        case .tile(let tileType):
            return tileBillboardPattern(for: tileType)
        }
    }

    private static func tileBillboardPattern(for tileType: TileType) -> [[Int]] {
        switch tileType {
        case .stairs:
            return [
                [1, 1, 1, 1],
                [1, 0, 0, 0],
                [1, 1, 1, 0]
            ]
        case .doorOpen:
            return [
                [1, 0, 1],
                [1, 0, 1],
                [1, 1, 1]
            ]
        case .brush:
            return [
                [1, 0, 1, 0],
                [0, 1, 0, 1],
                [1, 0, 1, 0]
            ]
        case .shrine:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0]
            ]
        case .beacon:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 1, 1]
            ]
        case .floor, .wall, .water, .doorLocked:
            return [[1]]
        }
    }

    private static func npcPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.npcSprite(for: id)?.pattern?.rows {
            return pattern
        }
        switch id {
        case "elder":
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1]
            ]
        case "field_scout":
            return [
                [1, 0, 1],
                [0, 1, 0],
                [0, 1, 0]
            ]
        case "orchard_guide":
            return [
                [0, 1, 0],
                [1, 1, 0],
                [0, 1, 1]
            ]
        default:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0]
            ]
        }
    }

    private static func enemyPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows {
            return pattern
        }
        if id.hasPrefix("crow") {
            return [
                [1, 0, 1],
                [1, 1, 1],
                [0, 1, 0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1, 1, 0],
                [1, 1, 1],
                [0, 1, 1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 1, 1]
            ]
        }
        return [
            [1, 1, 1],
            [1, 0, 1],
            [1, 1, 1]
        ]
    }

    private static func shaded(_ color: SDLColor, intensity: Double) -> SDLColor {
        SDLColor(
            r: UInt8(max(0, min(255, Int(Double(color.r) * intensity)))),
            g: UInt8(max(0, min(255, Int(Double(color.g) * intensity)))),
            b: UInt8(max(0, min(255, Int(Double(color.b) * intensity)))),
            a: color.a
        )
    }

    private static func blended(_ from: SDLColor, toward to: SDLColor, amount: Double) -> SDLColor {
        let t = max(0.0, min(1.0, amount))
        let r = Int((Double(from.r) * (1.0 - t)) + (Double(to.r) * t))
        let g = Int((Double(from.g) * (1.0 - t)) + (Double(to.g) * t))
        let b = Int((Double(from.b) * (1.0 - t)) + (Double(to.b) * t))
        let a = Int((Double(from.a) * (1.0 - t)) + (Double(to.a) * t))
        return SDLColor(
            r: UInt8(max(0, min(255, r))),
            g: UInt8(max(0, min(255, g))),
            b: UInt8(max(0, min(255, b))),
            a: UInt8(max(0, min(255, a)))
        )
    }

    private static func drawLine(
        _ renderer: OpaquePointer,
        fromX: Int,
        fromY: Int,
        toX: Int,
        toY: Int,
        color: SDLColor
    ) {
        var x0 = fromX
        var y0 = fromY
        let x1 = toX
        let y1 = toY
        let dx = abs(x1 - x0)
        let dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx - dy

        while true {
            fill(renderer, x: x0, y: y0, width: 1, height: 1, color: color)
            if x0 == x1, y0 == y1 {
                break
            }

            let e2 = err * 2
            if e2 > -dy {
                err -= dy
                x0 += sx
            }
            if e2 < dx {
                err += dx
                y0 += sy
            }
        }
    }

    private static func drawPattern(
        _ pattern: [[Int]],
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        color: SDLColor,
        renderer: OpaquePointer,
        shadowOffset: Int = 0
    ) {
        guard width > 0, height > 0 else { return }
        let rows = max(1, pattern.count)
        let columns = max(1, pattern.first?.count ?? 1)
        let pixelWidth = max(1, width / columns)
        let pixelHeight = max(1, height / rows)
        let drawWidth = pixelWidth * columns
        let drawHeight = pixelHeight * rows
        let originX = x + max(0, (width - drawWidth) / 2)
        let originY = y + max(0, (height - drawHeight) / 2)

        if shadowOffset > 0 {
            for (rowIndex, row) in pattern.enumerated() {
                for (columnIndex, value) in row.enumerated() where value == 1 {
                    fill(
                        renderer,
                        x: originX + (columnIndex * pixelWidth) + shadowOffset,
                        y: originY + (rowIndex * pixelHeight) + shadowOffset,
                        width: pixelWidth,
                        height: pixelHeight,
                        color: .shadow
                    )
                }
            }
        }

        for (rowIndex, row) in pattern.enumerated() {
            for (columnIndex, value) in row.enumerated() where value == 1 {
                fill(
                    renderer,
                    x: originX + (columnIndex * pixelWidth),
                    y: originY + (rowIndex * pixelHeight),
                    width: pixelWidth,
                    height: pixelHeight,
                    color: color
                )
            }
        }
    }

    private static func drawGlyph(
        _ character: Character,
        x: Int,
        y: Int,
        color: SDLColor,
        scale: Int,
        renderer: OpaquePointer
    ) {
        let rows = sdlBitmapFont[character] ?? sdlBitmapFont["?"]!
        for (rowIndex, rowMask) in rows.enumerated() {
            for columnIndex in 0..<3 {
                let bit = UInt8(1 << (2 - columnIndex))
                if rowMask & bit == 0 {
                    continue
                }
                fill(
                    renderer,
                    x: x + (columnIndex * scale),
                    y: y + (rowIndex * scale),
                    width: scale,
                    height: scale,
                    color: color
                )
            }
        }
    }

    private static func drawText(_ text: String, x: Int, y: Int, color: SDLColor, renderer: OpaquePointer) {
        let scale = 2
        let advance = (3 * scale) + scale + 1
        var cursorX = x

        for character in text.uppercased() {
            drawGlyph(character, x: cursorX, y: y, color: color, scale: scale, renderer: renderer)
            cursorX += advance
        }
    }

    @discardableResult
    private static func drawWrappedText(
        _ text: String,
        x: Int,
        y: Int,
        width: Int,
        color: SDLColor,
        renderer: OpaquePointer
    ) -> Int {
        var nextY = y
        for line in wrap(text, width: width) {
            drawText(line, x: x, y: nextY, color: color, renderer: renderer)
            nextY += 14
        }
        return nextY
    }

    private static func fill(_ renderer: OpaquePointer, x: Int, y: Int, width: Int, height: Int, color: SDLColor) {
        guard width > 0, height > 0 else { return }
        var rect = SDL_FRect(x: Float(x), y: Float(y), w: Float(width), h: Float(height))
        _ = SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
        _ = SDL_RenderFillRect(renderer, &rect)
    }

    private static func stroke(_ renderer: OpaquePointer, frame: SDLRect, color: SDLColor) {
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: 2, color: color)
        fill(renderer, x: frame.x, y: frame.y + frame.height - 2, width: frame.width, height: 2, color: color)
        fill(renderer, x: frame.x, y: frame.y, width: 2, height: frame.height, color: color)
        fill(renderer, x: frame.x + frame.width - 2, y: frame.y, width: 2, height: frame.height, color: color)
    }

    private static func wrap(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [text] }
        var lines: [String] = []
        var current = ""

        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            if candidate.count > width, !current.isEmpty {
                lines.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private static func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }

    private static func visibleInventoryEntries(_ scene: GraphicsSceneSnapshot) -> ArraySlice<InventoryEntrySnapshot> {
        guard scene.inventoryEntries.count > 8 else {
            return scene.inventoryEntries[...]
        }
        let center = max(0, min(scene.inventorySelectionIndex, scene.inventoryEntries.count - 1))
        let start = max(0, min(center - 3, scene.inventoryEntries.count - 8))
        let end = min(scene.inventoryEntries.count, start + 8)
        return scene.inventoryEntries[start..<end]
    }

    private static func visibleShopOffers(_ scene: GraphicsSceneSnapshot) -> ArraySlice<ShopOfferSnapshot> {
        guard scene.shopOffers.count > 6 else {
            return scene.shopOffers[...]
        }
        let center = max(0, min(scene.shopSelectionIndex, scene.shopOffers.count - 1))
        let start = max(0, min(center - 2, scene.shopOffers.count - 6))
        let end = min(scene.shopOffers.count, start + 6)
        return scene.shopOffers[start..<end]
    }

    private static func floorPattern(for mapID: String) -> SDLFloorPattern {
        if let overridePattern = GraphicsAssetCatalog.floorPattern(for: mapID) {
            return sdlFloorPattern(from: overridePattern)
        }
        switch mapID {
        case "merrow_village":
            return .brick
        case "south_fields":
            return .speckle
        case "sunken_orchard":
            return .weave
        case "hollow_barrows":
            return .hash
        case "black_fen":
            return .mire
        case "beacon_spire":
            return .circuit
        default:
            return .brick
        }
    }

    private static func sdlFloorPattern(from pattern: GraphicsFloorPatternName) -> SDLFloorPattern {
        switch pattern {
        case .brick:
            return .brick
        case .speckle:
            return .speckle
        case .weave:
            return .weave
        case .hash:
            return .hash
        case .mire:
            return .mire
        case .circuit:
            return .circuit
        }
    }

    private static func editorBoardTheme() -> SDLBoardTheme {
        SDLBoardTheme(
            frameBackground: .editorPanel,
            boardBackground: .editorBoard,
            outerBorder: .editorAccent,
            innerBorder: .bright.withAlpha(120),
            grid: .editorGrid,
            innerInset: 4,
            contentInset: 8,
            floor: .editorFloor,
            wall: SDLColor(r: 92, g: 108, b: 136, a: 255),
            water: SDLColor(r: 36, g: 112, b: 168, a: 255),
            brush: SDLColor(r: 54, g: 146, b: 78, a: 255),
            doorLocked: SDLColor(r: 198, g: 126, b: 54, a: 255),
            doorOpen: SDLColor(r: 230, g: 200, b: 104, a: 255),
            shrine: SDLColor(r: 168, g: 96, b: 214, a: 255),
            stairs: SDLColor(r: 152, g: 118, b: 84, a: 255),
            beacon: SDLColor(r: 118, g: 220, b: 228, a: 255)
        )
    }

    private static func boardTheme(for scene: GraphicsSceneSnapshot) -> SDLBoardTheme {
        let pattern = floorPattern(for: scene.currentMapID)
        let base: SDLBoardTheme
        switch scene.visualTheme {
        case .gemstone:
            base = SDLBoardTheme(
                frameBackground: .void,
                boardBackground: .void,
                outerBorder: .gold,
                innerBorder: .bright.withAlpha(130),
                grid: .grid,
                innerInset: 4,
                contentInset: 8,
                floor: floorBaseColor(for: pattern, variant: .gemstone),
                wall: .wall,
                water: .water,
                brush: .brush,
                doorLocked: .doorLocked,
                doorOpen: .doorOpen,
                shrine: .shrine,
                stairs: .stairs,
                beacon: .beacon
            )
        case .ultima:
            base = SDLBoardTheme(
                frameBackground: .ground,
                boardBackground: .ground.withAlpha(255),
                outerBorder: .bright.withAlpha(180),
                innerBorder: .wallShade,
                grid: .wallShade.withAlpha(110),
                innerInset: 2,
                contentInset: 4,
                floor: floorBaseColor(for: pattern, variant: .ultima),
                wall: .wall,
                water: .water,
                brush: .brush,
                doorLocked: .doorLocked,
                doorOpen: .doorOpen,
                shrine: .shrine,
                stairs: .stairs,
                beacon: .beacon
            )
        case .depth3D:
            base = SDLBoardTheme(
                frameBackground: .void,
                boardBackground: .void,
                outerBorder: .gold,
                innerBorder: .bright.withAlpha(120),
                grid: .grid,
                innerInset: 4,
                contentInset: 8,
                floor: floorBaseColor(for: pattern, variant: .gemstone),
                wall: .wall,
                water: .water,
                brush: .brush,
                doorLocked: .doorLocked,
                doorOpen: .doorOpen,
                shrine: .shrine,
                stairs: .stairs,
                beacon: .beacon
            )
        }
        return applyMapThemeOverrides(base: base, mapID: scene.currentMapID)
    }

    private static func applyMapThemeOverrides(base: SDLBoardTheme, mapID: String) -> SDLBoardTheme {
        guard let override = GraphicsAssetCatalog.mapTheme(for: mapID) else {
            return base
        }

        return SDLBoardTheme(
            frameBackground: override.roomShadow.map(SDLColor.init) ?? base.frameBackground,
            boardBackground: override.floor.map(SDLColor.init) ?? base.boardBackground,
            outerBorder: override.roomBorder.map(SDLColor.init) ?? base.outerBorder,
            innerBorder: override.roomHighlight.map(SDLColor.init) ?? base.innerBorder,
            grid: override.roomShadow.map(SDLColor.init) ?? base.grid,
            innerInset: base.innerInset,
            contentInset: base.contentInset,
            floor: override.floor.map(SDLColor.init) ?? base.floor,
            wall: override.wall.map(SDLColor.init) ?? base.wall,
            water: override.water.map(SDLColor.init) ?? base.water,
            brush: override.brush.map(SDLColor.init) ?? base.brush,
            doorLocked: override.doorLocked.map(SDLColor.init) ?? base.doorLocked,
            doorOpen: override.doorOpen.map(SDLColor.init) ?? base.doorOpen,
            shrine: override.shrine.map(SDLColor.init) ?? base.shrine,
            stairs: override.stairs.map(SDLColor.init) ?? base.stairs,
            beacon: override.beacon.map(SDLColor.init) ?? base.beacon
        )
    }

    private static func floorBaseColor(for pattern: SDLFloorPattern, variant: SDLBoardVariant) -> SDLColor {
        switch (pattern, variant) {
        case (.brick, .gemstone):
            return SDLColor(r: 54, g: 30, b: 20, a: 255)
        case (.speckle, .gemstone):
            return SDLColor(r: 70, g: 46, b: 18, a: 255)
        case (.weave, .gemstone):
            return SDLColor(r: 44, g: 36, b: 18, a: 255)
        case (.hash, .gemstone):
            return SDLColor(r: 32, g: 24, b: 26, a: 255)
        case (.mire, .gemstone):
            return SDLColor(r: 22, g: 34, b: 20, a: 255)
        case (.circuit, .gemstone):
            return SDLColor(r: 20, g: 20, b: 36, a: 255)
        case (.brick, .ultima):
            return SDLColor(r: 64, g: 48, b: 24, a: 255)
        case (.speckle, .ultima):
            return SDLColor(r: 78, g: 58, b: 24, a: 255)
        case (.weave, .ultima):
            return SDLColor(r: 56, g: 46, b: 22, a: 255)
        case (.hash, .ultima):
            return SDLColor(r: 42, g: 34, b: 28, a: 255)
        case (.mire, .ultima):
            return SDLColor(r: 28, g: 40, b: 24, a: 255)
        case (.circuit, .ultima):
            return SDLColor(r: 28, g: 28, b: 40, a: 255)
        }
    }

    private static func currentViewport(for renderer: OpaquePointer) -> SDLViewport {
        var width = Int32(windowWidth)
        var height = Int32(windowHeight)
        if !SDL_GetCurrentRenderOutputSize(renderer, &width, &height) {
            width = Int32(windowWidth)
            height = Int32(windowHeight)
        }

        let safeWidth = max(640, Int(width))
        let safeHeight = max(480, Int(height))
        let margin = max(16, min(28, safeWidth / 48))
        let gap = max(10, min(18, safeWidth / 96))
        let headerHeight = 20
        let contentY = margin + headerHeight
        let contentHeight = max(220, safeHeight - contentY - margin)
        let contentWidth = safeWidth - (margin * 2)
        let wideLayout = safeWidth >= 980 && contentHeight >= 360

        let headerFrame = SDLRect(x: margin, y: margin - 2, width: contentWidth, height: headerHeight)
        let contentFrame = SDLRect(x: margin, y: contentY, width: contentWidth, height: contentHeight)

        if wideLayout {
            let panelWidth = min(440, max(300, contentWidth / 3))
            let boardWidth = max(220, contentWidth - gap - panelWidth)
            return SDLViewport(
                width: safeWidth,
                height: safeHeight,
                headerFrame: headerFrame,
                contentFrame: contentFrame,
                boardFrame: SDLRect(x: margin, y: contentY, width: boardWidth, height: contentHeight),
                panelFrame: SDLRect(x: margin + boardWidth + gap, y: contentY, width: panelWidth, height: contentHeight),
                stacked: false
            )
        }

        let boardHeight = max(200, min(contentHeight - 140, Int(Double(contentHeight) * 0.56)))
        let panelY = contentY + boardHeight + gap
        let panelHeight = max(120, safeHeight - panelY - margin)

        return SDLViewport(
            width: safeWidth,
            height: safeHeight,
            headerFrame: headerFrame,
            contentFrame: contentFrame,
            boardFrame: SDLRect(x: margin, y: contentY, width: contentWidth, height: boardHeight),
            panelFrame: SDLRect(x: margin, y: panelY, width: contentWidth, height: panelHeight),
            stacked: true
        )
    }

    private static func sdlError() -> String {
        if let pointer = SDL_GetError() {
            return String(cString: pointer)
        }
        return "unknown error"
    }
}

private struct SDLRect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func insetBy(dx: Int, dy: Int) -> SDLRect {
        SDLRect(
            x: x + dx,
            y: y + dy,
            width: max(0, width - (dx * 2)),
            height: max(0, height - (dy * 2))
        )
    }
}

private struct SDLViewport {
    let width: Int
    let height: Int
    let headerFrame: SDLRect
    let contentFrame: SDLRect
    let boardFrame: SDLRect
    let panelFrame: SDLRect
    let stacked: Bool
}

private enum SDLFloorPattern {
    case brick
    case speckle
    case weave
    case hash
    case mire
    case circuit
}

private enum SDLBoardVariant {
    case gemstone
    case ultima
}

private struct SDLBoardTheme {
    let frameBackground: SDLColor
    let boardBackground: SDLColor
    let outerBorder: SDLColor
    let innerBorder: SDLColor
    let grid: SDLColor
    let innerInset: Int
    let contentInset: Int
    let floor: SDLColor
    let wall: SDLColor
    let water: SDLColor
    let brush: SDLColor
    let doorLocked: SDLColor
    let doorOpen: SDLColor
    let shrine: SDLColor
    let stairs: SDLColor
    let beacon: SDLColor
}

private struct SDLColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ color: GraphicsRGBColor) {
        self.init(
            r: UInt8(clamping: color.r),
            g: UInt8(clamping: color.g),
            b: UInt8(clamping: color.b),
            a: 255
        )
    }

    static let background = SDLColor(r: 6, g: 6, b: 8, a: 255)
    static let panel = SDLColor(r: 18, g: 18, b: 14, a: 255)
    static let void = SDLColor(r: 0, g: 0, b: 0, a: 255)
    static let gold = SDLColor(r: 238, g: 140, b: 18, a: 255)
    static let bright = SDLColor(r: 244, g: 238, b: 214, a: 255)
    static let dim = SDLColor(r: 170, g: 164, b: 140, a: 255)
    static let blue = SDLColor(r: 42, g: 132, b: 216, a: 255)
    static let green = SDLColor(r: 62, g: 180, b: 58, a: 255)
    static let violet = SDLColor(r: 170, g: 68, b: 198, a: 255)
    static let ground = SDLColor(r: 56, g: 40, b: 18, a: 255)
    static let wall = SDLColor(r: 108, g: 104, b: 118, a: 255)
    static let wallShade = SDLColor(r: 56, g: 52, b: 62, a: 255)
    static let water = SDLColor(r: 30, g: 88, b: 148, a: 255)
    static let brush = SDLColor(r: 36, g: 120, b: 36, a: 255)
    static let doorLocked = SDLColor(r: 170, g: 118, b: 30, a: 255)
    static let doorOpen = SDLColor(r: 230, g: 210, b: 90, a: 255)
    static let shrine = SDLColor(r: 144, g: 70, b: 200, a: 255)
    static let stairs = SDLColor(r: 128, g: 88, b: 44, a: 255)
    static let beacon = SDLColor(r: 244, g: 226, b: 74, a: 255)
    static let sky = SDLColor(r: 20, g: 46, b: 82, a: 255)
    static let ceiling = SDLColor(r: 10, g: 10, b: 16, a: 255)
    static let floor = SDLColor(r: 24, g: 20, b: 16, a: 255)
    static let grid = SDLColor(r: 12, g: 12, b: 12, a: 255)
    static let shadow = SDLColor(r: 0, g: 0, b: 0, a: 120)
    static let overlay = SDLColor(r: 0, g: 0, b: 0, a: 188)
    static let editorBackdrop = SDLColor(r: 8, g: 18, b: 30, a: 255)
    static let editorPanel = SDLColor(r: 12, g: 28, b: 40, a: 255)
    static let editorBoard = SDLColor(r: 10, g: 22, b: 30, a: 255)
    static let editorFloor = SDLColor(r: 26, g: 54, b: 64, a: 255)
    static let editorGrid = SDLColor(r: 18, g: 60, b: 76, a: 255)
    static let editorAccent = SDLColor(r: 98, g: 228, b: 230, a: 255)

    func withAlpha(_ alpha: UInt8) -> SDLColor {
        SDLColor(r: r, g: g, b: b, a: alpha)
    }
}

private let sdlBitmapFont: [Character: [UInt8]] = [
    " ": [0, 0, 0, 0, 0],
    "!": [2, 2, 2, 0, 2],
    "\"": [5, 5, 0, 0, 0],
    "'": [2, 2, 0, 0, 0],
    "+": [0, 2, 7, 2, 0],
    ",": [0, 0, 0, 2, 4],
    "-": [0, 0, 7, 0, 0],
    ".": [0, 0, 0, 0, 2],
    "/": [1, 1, 2, 4, 4],
    ":": [0, 2, 0, 2, 0],
    "=": [0, 7, 0, 7, 0],
    ">": [4, 2, 1, 2, 4],
    "?": [6, 1, 2, 0, 2],
    "[": [6, 4, 4, 4, 6],
    "]": [3, 1, 1, 1, 3],
    "_": [0, 0, 0, 0, 7],
    "0": [7, 5, 5, 5, 7],
    "1": [2, 6, 2, 2, 7],
    "2": [6, 1, 7, 4, 7],
    "3": [6, 1, 6, 1, 6],
    "4": [5, 5, 7, 1, 1],
    "5": [7, 4, 6, 1, 6],
    "6": [3, 4, 6, 5, 2],
    "7": [7, 1, 1, 2, 2],
    "8": [2, 5, 2, 5, 2],
    "9": [2, 5, 3, 1, 6],
    "A": [2, 5, 7, 5, 5],
    "B": [6, 5, 6, 5, 6],
    "C": [3, 4, 4, 4, 3],
    "D": [6, 5, 5, 5, 6],
    "E": [7, 4, 6, 4, 7],
    "F": [7, 4, 6, 4, 4],
    "G": [3, 4, 5, 5, 3],
    "H": [5, 5, 7, 5, 5],
    "I": [7, 2, 2, 2, 7],
    "J": [1, 1, 1, 5, 2],
    "K": [5, 5, 6, 5, 5],
    "L": [4, 4, 4, 4, 7],
    "M": [5, 7, 7, 5, 5],
    "N": [5, 7, 7, 7, 5],
    "O": [2, 5, 5, 5, 2],
    "P": [6, 5, 6, 4, 4],
    "Q": [2, 5, 5, 3, 1],
    "R": [6, 5, 6, 5, 5],
    "S": [3, 4, 2, 1, 6],
    "T": [7, 2, 2, 2, 2],
    "U": [5, 5, 5, 5, 7],
    "V": [5, 5, 5, 5, 2],
    "W": [5, 5, 7, 7, 5],
    "X": [5, 5, 2, 5, 5],
    "Y": [5, 5, 2, 2, 2],
    "Z": [7, 1, 2, 4, 7]
]

private extension GraphicsSceneSnapshot {
    var modeLabel: String {
        switch mode {
        case .title:
            return "TITLE"
        case .characterCreation:
            return "CREATOR"
        case .exploration:
            return "EXPLORE"
        case .dialogue:
            return "DIALOGUE"
        case .inventory:
            return "PACK"
        case .shop:
            return "SHOP"
        case .combat:
            return "COMBAT"
        case .pause:
            return "PAUSE"
        case .gameOver:
            return "GAME OVER"
        case .ending:
            return "ENDING"
        }
    }
}
