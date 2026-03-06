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
    static let windowWidth = 1280
    static let windowHeight = 800
    private static let resizableWindowFlag: SDL_WindowFlags = 0x20

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
                do {
                    try automationRunner.step(
                        sendCommand: { session.send($0) },
                        warpPlayer: { mapID, position, facing in
                            try session.warp(mapID: mapID, position: position, facing: facing)
                        },
                        cycleTheme: { session.cycleVisualTheme() },
                        selectTheme: { session.selectVisualTheme($0) },
                        captureScreenshot: { label in
                            pendingScreenshotLabel = label ?? screenshotLabel(session: session, editorSession: nil)
                        }
                    )
                } catch {
                    running = false
                }
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

    static func sdlError() -> String {
        if let pointer = SDL_GetError() {
            return String(cString: pointer)
        }
        return "unknown error"
    }
}
