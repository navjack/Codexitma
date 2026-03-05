import CSDL3
import Foundation

extension SDLGraphicsLauncher {
    static func renderScene(
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

        if scene.visualTheme == .depth3D, let depth = scene.depth, scene.mode == .exploration || scene.mode == .pause {
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
        if scene.mode == .pause {
            renderPauseOverlay(scene, viewport: viewport, with: renderer)
        }
        if let editorPromptLines {
            renderEditorPrompt(lines: editorPromptLines, viewport: viewport, with: renderer)
        }
    }

    static func renderAdventureEditor(
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
        case .pause:
            renderPauseSidebar(scene, frame: frame, with: renderer)
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

    private static func renderPauseSidebar(_ scene: GraphicsSceneSnapshot, frame: SDLRect, with renderer: OpaquePointer) {
        var y = frame.y + 10
        let lineHeight = 12

        drawText("PAUSE", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
        y += 18
        drawWrappedText("LEAVE THIS ROAD OR RETURN TO IT.".uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)
        y += 34

        for option in scene.pauseOptions {
            let prefix = option.isSelected ? ">" : " "
            drawText("\(prefix) \(option.label.uppercased())", x: frame.x + 10, y: y, color: option.isSelected ? .gold : .bright, renderer: renderer)
            y += lineHeight
        }

        if let detail = scene.pauseDetail {
            y += 12
            drawText("DETAIL", x: frame.x + 10, y: y, color: .gold, renderer: renderer)
            y += 16
            _ = drawWrappedText(detail.uppercased(), x: frame.x + 10, y: y, width: 30, color: .bright, renderer: renderer)
        }

        drawText("W/S MENU  E CHOOSE  Q RESUME", x: frame.x + 10, y: frame.y + frame.height - 42, color: .bright, renderer: renderer)
        drawText("K SAVE  M EDIT  X QUIT", x: frame.x + 10, y: frame.y + frame.height - 26, color: .bright, renderer: renderer)
        drawText("T STYLE  F10 DBG  F12 SHOT", x: frame.x + 10, y: frame.y + frame.height - 12, color: .bright, renderer: renderer)
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

    private static func renderPauseOverlay(_ scene: GraphicsSceneSnapshot, viewport: SDLViewport, with renderer: OpaquePointer) {
        let frame = viewport.boardFrame.insetBy(dx: 68, dy: 52)
        let panel = SDLRect(x: frame.x, y: frame.y, width: frame.width, height: min(frame.height, 240))

        fill(renderer, x: panel.x, y: panel.y, width: panel.width, height: panel.height, color: .overlay)
        stroke(renderer, frame: panel, color: .gold)

        drawText("LEAVE ROAD?", x: panel.x + 16, y: panel.y + 14, color: .gold, renderer: renderer)
        var y = panel.y + 38
        y = drawWrappedText("YOU CAN RETURN TO THE TITLE SCREEN TO LOAD A DIFFERENT ADVENTURE.", x: panel.x + 16, y: y, width: 54, color: .bright, renderer: renderer)
        y += 10

        for option in scene.pauseOptions {
            let prefix = option.isSelected ? ">" : " "
            drawText("\(prefix) \(option.label.uppercased())", x: panel.x + 16, y: y, color: option.isSelected ? .gold : .bright, renderer: renderer)
            y += 16
        }

        if let detail = scene.pauseDetail {
            y += 10
            _ = drawWrappedText(detail.uppercased(), x: panel.x + 16, y: y, width: 54, color: .dim, renderer: renderer)
        }
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
}
