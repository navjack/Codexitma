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

    static func run(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil
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
            preferenceStore: .shared,
            soundEngine: defaultGraphicsSoundEngine()
        )
        var running = true

        while running {
            var event = SDL_Event()
            while SDL_PollEvent(&event) {
                if event.type == SDL_EVENT_QUIT.rawValue {
                    running = false
                } else if event.type == SDL_EVENT_KEY_DOWN.rawValue {
                    if event.key.repeat {
                        continue
                    }
                    if handleKey(
                        key: event.key.key,
                        session: session
                    ) {
                        running = false
                    }
                }
            }

            if session.state.shouldQuit {
                running = false
            }

            let scene = session.sceneSnapshot
            renderScene(scene, with: renderer)
            _ = SDL_RenderPresent(renderer)
            SDL_Delay(16)
        }
    }

    private static func handleKey(
        key: SDL_Keycode,
        session: SharedGameSession
    ) -> Bool {
        switch key {
        case SDLK_T:
            session.cycleVisualTheme()
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

    private static func renderScene(_ scene: GraphicsSceneSnapshot, with renderer: OpaquePointer) {
        let viewport = currentViewport(for: renderer)
        fill(renderer, x: 0, y: 0, width: viewport.width, height: viewport.height, color: .background)

        switch scene.mode {
        case .title:
            renderTitleScreen(scene, viewport: viewport, with: renderer)
            return
        case .characterCreation:
            renderCharacterCreationScreen(scene, viewport: viewport, with: renderer)
            return
        case .ending:
            renderEndingScreen(scene, viewport: viewport, with: renderer)
            return
        default:
            break
        }

        let boardFrame = viewport.boardFrame
        let panelFrame = viewport.panelFrame

        if scene.visualTheme == .depth3D, let depth = scene.depth, scene.mode == .exploration {
            renderDepth(depth, scene: scene, frame: boardFrame, with: renderer)
        } else {
            renderBoard(scene.board, frame: boardFrame, with: renderer)
        }

        fill(renderer, x: panelFrame.x, y: panelFrame.y, width: panelFrame.width, height: panelFrame.height, color: .panel)
        stroke(renderer, frame: panelFrame, color: .gold)

        renderSidebar(scene, frame: panelFrame, with: renderer)
        renderHeader(scene, frame: viewport.headerFrame, with: renderer)
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
        drawText("T STYLE  X QUIT", x: frame.x + 18, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
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
        drawText("T STYLE", x: frame.x + 18, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
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

    private static func renderHeader(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        drawText(scene.adventureTitle.uppercased(), x: frame.x + 4, y: frame.y, color: .gold, renderer: renderer)
        drawText(scene.visualTheme.displayName.uppercased(), x: frame.x + min(220, max(120, frame.width / 4)), y: frame.y, color: .bright, renderer: renderer)
        drawText(scene.modeLabel, x: frame.x + min(360, max(220, frame.width / 2)), y: frame.y, color: .dim, renderer: renderer)
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
        drawText("Q BACK  X QUIT  T STYLE", x: frame.x + 10, y: y, color: .bright, renderer: renderer)
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
        drawText("Q CLOSE", x: frame.x + 10, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
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

        drawText("W/S MOVE  E BUY  Q LEAVE", x: frame.x + 10, y: frame.y + frame.height - 28, color: .bright, renderer: renderer)
    }

    private static func renderBoard(_ board: MapBoardSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height, color: .void)
        stroke(renderer, frame: frame, color: .gold)

        guard board.width > 0, board.height > 0 else { return }
        let cellWidth = max(6, min((frame.width - 12) / board.width, (frame.height - 12) / board.height))
        let drawWidth = board.width * cellWidth
        let drawHeight = board.height * cellWidth
        let originX = frame.x + ((frame.width - drawWidth) / 2)
        let originY = frame.y + ((frame.height - drawHeight) / 2)

        for row in board.rows {
            for cell in row {
                let x = originX + (cell.position.x * cellWidth)
                let y = originY + (cell.position.y * cellWidth)
                fill(renderer, x: x, y: y, width: cellWidth, height: cellWidth, color: tileColor(for: cell.tile.type))
                drawTileAccent(for: cell.tile.type, x: x, y: y, cellSize: cellWidth, renderer: renderer)
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
                        shadowOffset: cellWidth >= 10 ? 1 : 0
                    )
                }
                if cellWidth >= 10 {
                    stroke(renderer, frame: SDLRect(x: x, y: y, width: cellWidth, height: cellWidth), color: .grid)
                }
            }
        }
    }

    private static func renderDepth(
        _ depth: DepthSceneSnapshot,
        scene: GraphicsSceneSnapshot,
        frame: SDLRect,
        with renderer: OpaquePointer
    ) {
        let horizon = frame.y + (frame.height / 2)
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: frame.height / 2, color: depth.usesSkyBackdrop ? .sky : .ceiling)
        fill(renderer, x: frame.x, y: horizon, width: frame.width, height: frame.height / 2, color: .floor)
        stroke(renderer, frame: frame, color: .gold)

        guard !depth.samples.isEmpty else { return }
        let columnWidth = max(1, frame.width / depth.samples.count)
        let zBuffer = depth.samples.map(\.correctedDistance)

        for sample in depth.samples where sample.didHit {
            let distance = max(0.14, sample.correctedDistance)
            let wallHeight = min(Double(frame.height) * 0.92, (Double(frame.height) * 0.82) / distance)
            let top = Int(Double(horizon) - (wallHeight * 0.5))
            let height = max(1, Int(wallHeight))
            let x = frame.x + (sample.column * columnWidth)
            let color = shaded(
                tileColor(for: sample.hitTile.type),
                intensity: max(0.22, 1.0 - ((sample.correctedDistance / depth.maxDistance) * 0.72))
            )
            fill(renderer, x: x, y: top, width: max(1, columnWidth + 1), height: height, color: color)
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
            let endSample = min(depth.samples.count - 1, (left - frame.x + width - 1) / columnWidth)
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

            drawPattern(
                billboardPattern(for: billboard.kind),
                x: left,
                y: top,
                width: width,
                height: height,
                color: billboardColor(for: billboard.kind),
                renderer: renderer,
                shadowOffset: width >= 14 ? 2 : 1
            )
        }

        let cx = frame.x + (frame.width / 2)
        let cy = frame.y + (frame.height / 2)
        fill(renderer, x: cx - 10, y: cy, width: 20, height: 2, color: .bright)
        fill(renderer, x: cx, y: cy - 10, width: 2, height: 20, color: .bright)
        drawText("VIEW \(scene.player.facing.shortLabel)", x: frame.x + 10, y: frame.y + 10, color: .gold, renderer: renderer)
    }

    private static func tileColor(for type: TileType) -> SDLColor {
        switch type {
        case .floor: return .ground
        case .wall: return .wall
        case .water: return .water
        case .brush: return .brush
        case .doorLocked: return .doorLocked
        case .doorOpen: return .doorOpen
        case .shrine: return .shrine
        case .stairs: return .stairs
        case .beacon: return .beacon
        }
    }

    private static func featureColor(for feature: MapFeature) -> SDLColor {
        switch feature {
        case .none: return .bright
        case .chest: return .gold
        case .bed: return .bright
        case .plateUp: return .violet
        case .plateDown: return .dim
        case .switchIdle: return .blue
        case .switchLit: return .gold
        case .shrine: return .violet
        case .beacon: return .beacon
        case .gate: return .doorLocked
        }
    }

    private static func occupantColor(for occupant: MapOccupant) -> SDLColor {
        switch occupant {
        case .none: return .bright
        case .player: return .bright
        case .npc: return .blue
        case .enemy: return .green
        case .boss: return .violet
        }
    }

    private static func billboardColor(for kind: DepthBillboardKind) -> SDLColor {
        switch kind {
        case .npc:
            return .blue
        case .enemy:
            return .green
        case .boss:
            return .violet
        case .feature(let feature):
            return featureColor(for: feature)
        }
    }

    private static func drawTileAccent(
        for type: TileType,
        x: Int,
        y: Int,
        cellSize: Int,
        renderer: OpaquePointer
    ) {
        switch type {
        case .floor:
            if cellSize >= 8 {
                fill(renderer, x: x + (cellSize / 3), y: y + (cellSize / 3), width: max(1, cellSize / 6), height: max(1, cellSize / 6), color: .wallShade)
            }
        case .wall:
            fill(renderer, x: x, y: y, width: cellSize, height: max(1, cellSize / 5), color: .wallShade)
            fill(renderer, x: x, y: y + (cellSize / 2), width: cellSize, height: max(1, cellSize / 6), color: .wallShade)
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

    private static func featurePattern(for feature: MapFeature) -> [[Int]] {
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
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1]
            ]
        case .npc(let id):
            return npcPattern(for: id)
        case .enemy(let id):
            return enemyPattern(for: id)
        case .boss:
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
        case .boss:
            return [
                [1, 0, 1],
                [1, 1, 1],
                [1, 1, 1]
            ]
        case .feature(let feature):
            return featurePattern(for: feature)
        }
    }

    private static func npcPattern(for id: String) -> [[Int]] {
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

private struct SDLColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

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
