import CSDL3
import Foundation

extension SDLGraphicsLauncher {
    static func shaded(_ color: SDLColor, intensity: Double) -> SDLColor {
        SDLColor(
            r: UInt8(max(0, min(255, Int(Double(color.r) * intensity)))),
            g: UInt8(max(0, min(255, Int(Double(color.g) * intensity)))),
            b: UInt8(max(0, min(255, Int(Double(color.b) * intensity)))),
            a: color.a
        )
    }

    static func blended(_ from: SDLColor, toward to: SDLColor, amount: Double) -> SDLColor {
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

    static func drawLine(
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

    static func drawPattern(
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

    static func drawGlyph(
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

    static func drawText(_ text: String, x: Int, y: Int, color: SDLColor, renderer: OpaquePointer) {
        let scale = 2
        let advance = (3 * scale) + scale + 1
        var cursorX = x

        for character in text.uppercased() {
            drawGlyph(character, x: cursorX, y: y, color: color, scale: scale, renderer: renderer)
            cursorX += advance
        }
    }

    @discardableResult
    static func drawWrappedText(
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

    static func fill(_ renderer: OpaquePointer, x: Int, y: Int, width: Int, height: Int, color: SDLColor) {
        guard width > 0, height > 0 else { return }
        var rect = SDL_FRect(x: Float(x), y: Float(y), w: Float(width), h: Float(height))
        _ = SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
        _ = SDL_RenderFillRect(renderer, &rect)
    }

    static func stroke(_ renderer: OpaquePointer, frame: SDLRect, color: SDLColor) {
        fill(renderer, x: frame.x, y: frame.y, width: frame.width, height: 2, color: color)
        fill(renderer, x: frame.x, y: frame.y + frame.height - 2, width: frame.width, height: 2, color: color)
        fill(renderer, x: frame.x, y: frame.y, width: 2, height: frame.height, color: color)
        fill(renderer, x: frame.x + frame.width - 2, y: frame.y, width: 2, height: frame.height, color: color)
    }

    static func wrap(_ text: String, width: Int) -> [String] {
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

    static func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }

    static func visibleInventoryEntries(_ scene: GraphicsSceneSnapshot) -> ArraySlice<InventoryEntrySnapshot> {
        guard scene.inventoryEntries.count > 8 else {
            return scene.inventoryEntries[...]
        }
        let center = max(0, min(scene.inventorySelectionIndex, scene.inventoryEntries.count - 1))
        let start = max(0, min(center - 3, scene.inventoryEntries.count - 8))
        let end = min(scene.inventoryEntries.count, start + 8)
        return scene.inventoryEntries[start..<end]
    }

    static func visibleShopOffers(_ scene: GraphicsSceneSnapshot) -> ArraySlice<ShopOfferSnapshot> {
        guard scene.shopOffers.count > 6 else {
            return scene.shopOffers[...]
        }
        let center = max(0, min(scene.shopSelectionIndex, scene.shopOffers.count - 1))
        let start = max(0, min(center - 2, scene.shopOffers.count - 6))
        let end = min(scene.shopOffers.count, start + 6)
        return scene.shopOffers[start..<end]
    }

    static func floorPattern(for mapID: String) -> SDLFloorPattern {
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

    static func sdlFloorPattern(from pattern: GraphicsFloorPatternName) -> SDLFloorPattern {
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

    static func editorBoardTheme() -> SDLBoardTheme {
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

    static func boardTheme(for scene: GraphicsSceneSnapshot) -> SDLBoardTheme {
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

    static func applyMapThemeOverrides(base: SDLBoardTheme, mapID: String) -> SDLBoardTheme {
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

    static func floorBaseColor(for pattern: SDLFloorPattern, variant: SDLBoardVariant) -> SDLColor {
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

    static func currentViewport(for renderer: OpaquePointer) -> SDLViewport {
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
}

struct SDLRect {
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

struct SDLViewport {
    let width: Int
    let height: Int
    let headerFrame: SDLRect
    let contentFrame: SDLRect
    let boardFrame: SDLRect
    let panelFrame: SDLRect
    let stacked: Bool
}

enum SDLFloorPattern {
    case brick
    case speckle
    case weave
    case hash
    case mire
    case circuit
}

enum SDLBoardVariant {
    case gemstone
    case ultima
}

struct SDLBoardTheme {
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

struct SDLColor {
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

extension GraphicsSceneSnapshot {
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
