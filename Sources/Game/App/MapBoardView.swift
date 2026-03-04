#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

private struct DepthTextureAtlas {
    let image: Image
    let cgImage: CGImage
    let textureWidth: CGFloat
    let textureHeight: CGFloat
    let tileSize: CGFloat
    let columns: Int

    func tileRect(id: Int) -> CGRect {
        let column = id % columns
        let row = id / columns
        return CGRect(
            x: CGFloat(column) * tileSize,
            y: CGFloat(row) * tileSize,
            width: tileSize,
            height: tileSize
        )
    }

    func wallRect(for tileType: TileType) -> CGRect {
        switch tileType {
        case .wall:
            return tileRect(id: 0)
        case .doorLocked:
            return tileRect(id: 27)
        case .doorOpen:
            return tileRect(id: 29)
        case .water:
            return tileRect(id: 78)
        case .brush:
            return tileRect(id: 60)
        case .shrine:
            return tileRect(id: 82)
        case .stairs:
            return tileRect(id: 26)
        case .beacon:
            return tileRect(id: 86)
        case .floor:
            return tileRect(id: 4)
        }
    }

    var floorRect: CGRect {
        tileRect(id: 4)
    }

    func wallSlice(for tileType: TileType, u: Double) -> CGImage? {
        let rect = wallRect(for: tileType)
        let clampedU = max(0.0, min(0.999, u))
        let x = Int(rect.minX + floor(CGFloat(clampedU) * rect.width))
        let y = Int(rect.minY)
        let crop = CGRect(x: x, y: y, width: 1, height: Int(rect.height))
        return cgImage.cropping(to: crop)
    }

    func floorPixel(u: CGFloat, v: CGFloat) -> CGImage? {
        let rect = floorRect
        let clampedU = max(0.0, min(0.999, u))
        let clampedV = max(0.0, min(0.999, v))
        let x = Int(rect.minX + floor(clampedU * rect.width))
        let y = Int(rect.minY + floor(clampedV * rect.height))
        let crop = CGRect(x: x, y: y, width: 1, height: 1)
        return cgImage.cropping(to: crop)
    }

    static func load(bundle: Bundle = GameResourceBundle.current) -> DepthTextureAtlas? {
        let candidates: [URL?] = [
            bundle.url(forResource: "punyworld-dungeon-tileset", withExtension: "png"),
            bundle.url(
                forResource: "punyworld-dungeon-tileset",
                withExtension: "png",
                subdirectory: "DepthTextures"
            ),
            bundle.url(
                forResource: "punyworld-dungeon-tileset",
                withExtension: "png",
                subdirectory: "ContentData/DepthTextures"
            ),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            return nil
        }
        guard let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let textureWidth = CGFloat(cgImage.width)
        let textureHeight = CGFloat(cgImage.height)
        let tileSize: CGFloat = 16
        let columns = Int(textureWidth / tileSize)

        return DepthTextureAtlas(
            image: Image(decorative: cgImage, scale: 1.0),
            cgImage: cgImage,
            textureWidth: textureWidth,
            textureHeight: textureHeight,
            tileSize: tileSize,
            columns: columns
        )
    }
}

struct MapBoardView: View {
    let state: GameState
    let scene: GraphicsSceneSnapshot
    let palette: UltimaPalette
    let visualTheme: GraphicsVisualTheme
    let showLightingDebug: Bool

    private let cell: CGFloat = 14
    private static let depthTextureAtlas = DepthTextureAtlas.load()

    var body: some View {
        if visualTheme == .depth3D {
            firstPersonView(theme: regionTheme)
        } else {
            topDownView(board: scene.board, theme: regionTheme)
        }
    }

    private func topDownView(board: MapBoardSnapshot, theme: RegionTheme) -> some View {
        let boardPadding = visualTheme == .gemstone ? 4.0 : 2.0
        let boardScale = visualTheme == .gemstone ? 2.0 : 1.84
        let boardWidth = CGFloat(board.width) * cell
        let boardHeight = CGFloat(board.height) * cell
        let lighting = scene.mapLighting
        let boardContent = AnyView(
            ZStack {
                VStack(spacing: 0) {
                    ForEach(Array(board.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.position) { cellSnapshot in
                                tileView(for: cellSnapshot, theme: theme)
                            }
                        }
                    }
                }
                if showLightingDebug, let lighting {
                    topDownLightingOverlay(board: board, lighting: lighting, theme: theme)
                }
            }
        )

        return ZStack(alignment: .topLeading) {
            if visualTheme == .gemstone {
                Rectangle()
                    .fill(theme.roomShadow)
                    .offset(x: 3, y: 3)
            }

            boardContent
                .padding(boardPadding)
                .background(visualTheme == .gemstone ? Color.black : theme.floor.opacity(0.22))
                .overlay(
                    Rectangle()
                        .stroke(
                            visualTheme == .gemstone ? theme.roomHighlight : palette.lightGold.opacity(0.75),
                            lineWidth: visualTheme == .gemstone ? 2 : 1
                        )
                        .padding(visualTheme == .gemstone ? 3 : 0)
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            visualTheme == .gemstone ? theme.roomBorder : palette.lightGold,
                            lineWidth: visualTheme == .gemstone ? 4 : 2
                        )
                )
        }
        .scaleEffect(boardScale, anchor: .topLeading)
        .frame(
            width: (boardWidth + (boardPadding * 2)) * boardScale,
            height: (boardHeight + (boardPadding * 2)) * boardScale,
            alignment: .topLeading
        )
        .clipped()
        .drawingGroup(opaque: false)
    }

    private func tileView(for cellSnapshot: BoardCellSnapshot, theme: RegionTheme) -> some View {
        let tileColor = cellSnapshot.tile
        let occupant = cellSnapshot.occupant
        let feature = cellSnapshot.feature

        return LowResTileView(
            tile: tileColor,
            occupant: occupant,
            feature: feature,
            palette: palette,
            regionTheme: theme,
            visualTheme: visualTheme
        )
        .frame(width: cell, height: cell)
    }

    private func topDownLightingOverlay(
        board: MapBoardSnapshot,
        lighting: DepthTileLightingSnapshot,
        theme: RegionTheme
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(board.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.position) { cellSnapshot in
                        let light = lighting.level(at: cellSnapshot.position)
                        let lift = max(0.0, light - lighting.ambient)
                        let dim = max(0.0, lighting.ambient - light)
                        ZStack {
                            if lift > 0.01 {
                                Rectangle()
                                    .fill(theme.roomHighlight.opacity(min(0.54, 0.10 + (lift * 0.85))))
                            }
                            if dim > 0.01 {
                                Rectangle()
                                    .fill(Color.black.opacity(min(0.54, 0.08 + (dim * 0.92))))
                            }
                        }
                        .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func firstPersonView(theme: RegionTheme) -> some View {
        GeometryReader { proxy in
            let depthScene = scene.depth
            let raySamples = depthScene?.samples ?? []
            let lighting = depthScene?.tileLighting ?? scene.mapLighting
            ZStack {
                Canvas { context, canvasSize in
                    drawDepthScene(into: &context, size: canvasSize, samples: raySamples, theme: theme)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("VIEW \((depthScene?.facing ?? scene.player.facing).shortLabel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)
                    Text("FIRST-PERSON")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.86))
                    Text("RAYCAST MAP  A/D TURN")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                    Text("W/S STEP  RANGE \(Int((depthScene?.maxDistance ?? 9).rounded())) TILES")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

                CrosshairView(color: palette.text.opacity(0.65))
                    .frame(width: 26, height: 26)

                if showLightingDebug, let lighting {
                    depthDebugOverlay(board: scene.board, lighting: lighting, theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(10)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(theme.roomHighlight.opacity(0.65), lineWidth: 2)
                    .padding(4)
            )
            .overlay(
                Rectangle()
                    .stroke(theme.roomBorder, lineWidth: 4)
            )
            .drawingGroup(opaque: false)
        }
        .frame(width: 584, height: 356)
    }

    private func depthDebugOverlay(
        board: MapBoardSnapshot,
        lighting: DepthTileLightingSnapshot,
        theme: RegionTheme
    ) -> some View {
        let levels = lighting.values.flatMap { $0 }
        let minLevel = levels.min() ?? lighting.ambient
        let maxLevel = levels.max() ?? lighting.ambient
        let avgLevel = levels.isEmpty ? lighting.ambient : (levels.reduce(0, +) / Double(levels.count))

        return VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG LIGHT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.lightGold)
            Text("AMB \(lightValueString(lighting.ambient))")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.90))
            Text("MIN \(lightValueString(minLevel)) MAX \(lightValueString(maxLevel))")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.90))
            Text("AVG \(lightValueString(avgLevel))")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.90))
            Text("P \(scene.player.position.x),\(scene.player.position.y) \(scene.player.facing.shortLabel)")
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.90))

            Canvas { context, size in
                guard board.width > 0, board.height > 0 else {
                    return
                }

                let stepX = size.width / CGFloat(board.width)
                let stepY = size.height / CGFloat(board.height)
                for row in board.rows {
                    for cell in row {
                        let rect = CGRect(
                            x: CGFloat(cell.position.x) * stepX,
                            y: CGFloat(cell.position.y) * stepY,
                            width: max(1, stepX),
                            height: max(1, stepY)
                        )
                        let level = lighting.level(at: cell.position)
                        let normalized = max(0.0, min(1.0, (level - lighting.ambient) * 1.8 + 0.26))
                        var color = Color(
                            red: 0.08 + (normalized * 0.88),
                            green: 0.08 + (normalized * 0.78),
                            blue: 0.09 + (normalized * 0.64)
                        )
                        if !cell.tile.walkable {
                            color = Color(
                                red: 0.10 + (normalized * 0.32),
                                green: 0.10 + (normalized * 0.28),
                                blue: 0.12 + (normalized * 0.24)
                            )
                        }
                        context.fill(Path(rect), with: .color(color))

                        if !cell.tile.walkable {
                            context.stroke(
                                Path(rect),
                                with: .color(Color.black.opacity(0.42)),
                                lineWidth: max(1, min(stepX, stepY) * 0.14)
                            )
                        }

                        if cell.feature == .torchFloor || cell.feature == .torchWall {
                            let dot = CGRect(
                                x: rect.midX - (stepX * 0.18),
                                y: rect.midY - (stepY * 0.18),
                                width: stepX * 0.36,
                                height: stepY * 0.36
                            )
                            context.fill(Path(ellipseIn: dot), with: .color(palette.lightGold))
                        }
                    }
                }

                let playerRect = CGRect(
                    x: CGFloat(scene.player.position.x) * stepX,
                    y: CGFloat(scene.player.position.y) * stepY,
                    width: max(1, stepX),
                    height: max(1, stepY)
                ).insetBy(dx: stepX * 0.16, dy: stepY * 0.16)
                context.fill(Path(playerRect), with: .color(palette.accentBlue))
            }
            .frame(width: 168, height: 110)
            .background(Color.black.opacity(0.46))
            .overlay(Rectangle().stroke(theme.roomHighlight.opacity(0.58), lineWidth: 1))
        }
        .padding(8)
        .background(Color.black.opacity(0.76))
        .overlay(Rectangle().stroke(theme.roomBorder.opacity(0.82), lineWidth: 2))
        .overlay(Rectangle().inset(by: 3).stroke(theme.roomHighlight.opacity(0.44), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func drawDepthScene(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        drawDepthBackdrop(into: &context, size: size, theme: theme)
        drawDepthWalls(into: &context, size: size, samples: samples, theme: theme)
        drawDepthBillboards(into: &context, size: size, samples: samples, theme: theme)
        drawDepthReticleGlow(into: &context, size: size)
    }

    private func drawDepthBackdrop(
        into context: inout GraphicsContext,
        size: CGSize,
        theme: RegionTheme
    ) {
        let horizon = size.height * 0.5
        let ceilingRect = CGRect(x: 0, y: 0, width: size.width, height: horizon)
        let floorRect = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
        let stripeStrength: Double
        let floorBands: Int
        let floorLighting = scene.depth?.floorLighting
        let worldLighting = scene.depth?.worldLighting
        let depthTextureAtlas = Self.depthTextureAtlas
        let facing = scene.depth?.facing ?? scene.player.facing
        let fieldOfView = scene.depth?.fieldOfView ?? depthFieldOfView
        switch theme.pattern {
        case .brick:
            stripeStrength = 0.08
            floorBands = 15
        case .speckle:
            stripeStrength = 0.05
            floorBands = 13
        case .weave:
            stripeStrength = 0.07
            floorBands = 16
        case .hash:
            stripeStrength = 0.06
            floorBands = 12
        case .mire:
            stripeStrength = 0.09
            floorBands = 14
        case .circuit:
            stripeStrength = 0.08
            floorBands = 18
        }

        if scene.depth?.usesSkyBackdrop ?? true {
            context.fill(
                Path(ceilingRect),
                with: .linearGradient(
                    Gradient(colors: [
                        theme.roomHighlight.opacity(0.34),
                        theme.roomShadow.opacity(0.86)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: horizon)
                )
            )

            for band in 0..<5 {
                let y = horizon * (0.12 + (CGFloat(band) * 0.13))
                let width = size.width * (0.16 + (CGFloat(band % 3) * 0.08))
                let x = (size.width * 0.18) + (CGFloat((band * 17) % 41) / 100.0) * size.width
                let cloud = CGRect(x: min(x, size.width - width), y: y, width: width, height: 3)
                context.fill(Path(cloud), with: .color(theme.roomHighlight.opacity(0.08)))
            }
        } else {
            context.fill(
                Path(ceilingRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color.black.opacity(0.98),
                        theme.wall.opacity(0.34)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: horizon)
                )
            )

            for row in 1...8 {
                let t = CGFloat(row) / 8.0
                let y = horizon * pow(t, 1.65)
                let line = Path(CGRect(x: 0, y: y, width: size.width, height: 1))
                context.fill(line, with: .color(theme.roomHighlight.opacity(0.05)))
            }
        }

        context.fill(Path(floorRect), with: .color(theme.floor.opacity(0.18)))

        for band in 0..<floorBands {
            let t0 = CGFloat(band) / CGFloat(floorBands)
            let t1 = CGFloat(band + 1) / CGFloat(floorBands)
            let y0 = horizon + (size.height - horizon) * pow(t0, 1.6)
            let y1 = horizon + (size.height - horizon) * pow(t1, 1.6)
            let rect = CGRect(x: 0, y: y0, width: size.width, height: max(1, y1 - y0))
            let shade = 0.10 + (Double(t1) * 0.22)
            let stripe = band.isMultiple(of: 2)
                ? theme.roomHighlight.opacity(stripeStrength)
                : Color.black.opacity(max(0.03, stripeStrength - 0.02))
            if let depthTextureAtlas {
                drawTexturedFloorBand(
                    into: &context,
                    rect: rect,
                    atlas: depthTextureAtlas,
                    floorLighting: floorLighting,
                    worldLighting: worldLighting,
                    theme: theme,
                    horizon: horizon,
                    canvasSize: size,
                    fieldOfView: fieldOfView,
                    facing: facing,
                    floorBands: floorBands,
                    bandIndex: band
                )
                context.fill(Path(rect), with: .color(Color.black.opacity(0.06 + (Double(t1) * 0.10))))
                context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe.opacity(0.16)))
            } else {
                context.fill(Path(rect), with: .color(theme.floor.opacity(shade)))
                context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe))
            }

            if band > 0 {
                let line = Path(CGRect(x: 0, y: y0, width: size.width, height: 1))
                context.fill(line, with: .color(theme.roomHighlight.opacity(0.06)))
            }
        }

        let center = CGPoint(x: size.width * 0.5, y: horizon)
        for step in stride(from: -0.8, through: 0.8, by: 0.2) {
            let end = CGPoint(x: size.width * (0.5 + (step * 0.55)), y: size.height)
            var guide = Path()
            guide.move(to: center)
            guide.addLine(to: end)
            context.stroke(guide, with: .color(theme.roomHighlight.opacity(0.04)), lineWidth: 1)
        }

        let horizonLine = Path(CGRect(x: 0, y: horizon, width: size.width, height: 1))
        context.fill(horizonLine, with: .color(theme.roomHighlight.opacity(0.10)))

        let sideVignetteWidth = size.width * 0.09
        context.fill(
            Path(CGRect(x: 0, y: 0, width: sideVignetteWidth, height: size.height)),
            with: .color(Color.black.opacity(0.16))
        )
        context.fill(
            Path(CGRect(x: size.width - sideVignetteWidth, y: 0, width: sideVignetteWidth, height: size.height)),
            with: .color(Color.black.opacity(0.16))
        )
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.08)),
            with: .color(Color.black.opacity(0.14))
        )
    }

    private func drawTexturedFloorBand(
        into context: inout GraphicsContext,
        rect: CGRect,
        atlas: DepthTextureAtlas,
        floorLighting: DepthFloorLightingSnapshot?,
        worldLighting: DepthWorldLightingSnapshot?,
        theme: RegionTheme,
        horizon: CGFloat,
        canvasSize: CGSize,
        fieldOfView: Double,
        facing: Direction,
        floorBands: Int,
        bandIndex: Int
    ) {
        let forward = facingUnitVector(for: facing)
        let right = rightUnitVector(for: facing)
        let planeScale = tan(fieldOfView * 0.5)
        let leftRay = (x: forward.x - (right.x * planeScale), y: forward.y - (right.y * planeScale))
        let rightRay = (x: forward.x + (right.x * planeScale), y: forward.y + (right.y * planeScale))

        let playerX = Double(scene.player.position.x) + 0.5
        let playerY = Double(scene.player.position.y) + 0.5
        let rowScreenY = max(horizon + 1, rect.midY)
        let rowDepth = max(1.0, Double(rowScreenY - horizon))
        let posZ = Double(canvasSize.height) * 0.50
        let bandNorm = (Double(bandIndex) + 0.5) / Double(max(1, floorBands))
        let normalizedScreenDepth = max(
            0.0,
            min(1.0, Double((rowScreenY - horizon) / max(1.0, canvasSize.height - horizon)))
        )
        let perspectiveWarp = 0.72 + (pow(1.0 - normalizedScreenDepth, 1.55) * 0.65)
        let rowDistance = (posZ / rowDepth) * perspectiveWarp
        let stripScale = 0.78 + (pow(1.0 - bandNorm, 1.2) * 0.72)
        let stripCount = max(96, Int((Double(canvasSize.width) * 0.52) * stripScale))
        var stripLightLevels = Array(repeating: floorLighting?.ambient ?? worldLighting?.ambient ?? 0.20, count: stripCount)

        context.withCGContext { cgContext in
            cgContext.interpolationQuality = .none
            for strip in 0..<stripCount {
                let xNorm = (Double(strip) + 0.5) / Double(stripCount)
                let rayX = leftRay.x + ((rightRay.x - leftRay.x) * xNorm)
                let rayY = leftRay.y + ((rightRay.y - leftRay.y) * xNorm)
                let worldX = playerX + (rowDistance * rayX)
                let worldY = playerY + (rowDistance * rayY)
                let u = fract(worldX)
                let v = fract(worldY)

                let x0 = rect.minX + (CGFloat(strip) / CGFloat(stripCount)) * rect.width
                let x1 = rect.minX + (CGFloat(strip + 1) / CGFloat(stripCount)) * rect.width
                let stripe = CGRect(
                    x: x0,
                    y: rect.minY,
                    width: max(1, x1 - x0),
                    height: rect.height
                )
                if let pixel = atlas.floorPixel(u: u, v: v) {
                    cgContext.draw(pixel, in: stripe)
                }

                let light = worldLighting?.level(atWorldX: worldX, y: worldY)
                    ?? floorLighting?.interpolatedLevel(
                        xNormalized: xNorm,
                        yNormalized: bandNorm
                    )
                    ?? (floorLighting?.ambient ?? worldLighting?.ambient ?? 0.20)
                stripLightLevels[strip] = light
            }
        }

        let ambient = floorLighting?.ambient ?? worldLighting?.ambient
        if let ambient {
            for strip in 0..<stripCount {
                let x0 = rect.minX + (CGFloat(strip) / CGFloat(stripCount)) * rect.width
                let x1 = rect.minX + (CGFloat(strip + 1) / CGFloat(stripCount)) * rect.width
                let stripe = CGRect(
                    x: x0,
                    y: rect.minY,
                    width: max(1, x1 - x0),
                    height: rect.height
                )
                let light = stripLightLevels[strip]
                let lift = max(0.0, light - ambient)
                let dim = max(0.0, ambient - light)
                if lift > 0.01 {
                    let glow = theme.roomHighlight.opacity(min(0.44, 0.05 + (lift * 0.60)))
                    context.fill(Path(stripe), with: .color(glow))
                }
                if dim > 0.01 {
                    let shadow = Color.black.opacity(min(0.24, 0.04 + (dim * 0.38)))
                    context.fill(Path(stripe), with: .color(shadow))
                }
            }
        }
    }

    private func drawDepthWalls(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        guard !samples.isEmpty else { return }

        let horizon = size.height * 0.5
        let columnWidth = size.width / CGFloat(samples.count)
        let depthTextureAtlas = Self.depthTextureAtlas

        for sample in samples where sample.didHit {
            let distance = max(0.14, sample.correctedDistance)
            let wallHeight = min(size.height * 0.92, (size.height * 0.82) / CGFloat(distance))
            let top = max(0, horizon - (wallHeight * 0.5))
            let rect = CGRect(
                x: CGFloat(sample.column) * columnWidth,
                y: top,
                width: ceil(columnWidth) + 1,
                height: min(size.height - top, wallHeight)
            )

            let axisShade = sample.hitAxis == .vertical ? 0.78 : 0.92
            let distanceShade = max(0.20, 1.0 - ((sample.correctedDistance / sample.maxDistance) * 0.76))
            let lightShade = max(0.18, min(1.0, sample.lightLevel))
            if let depthTextureAtlas {
                context.withCGContext { cgContext in
                    cgContext.interpolationQuality = .none
                    if let slice = depthTextureAtlas.wallSlice(for: sample.hitTile.type, u: sample.textureU) {
                        cgContext.draw(slice, in: rect)
                    }
                }
                let tint = frontWallColor(for: sample.hitTile, theme: theme).opacity(0.20)
                context.fill(Path(rect), with: .color(tint))
            } else {
                let wallColor = frontWallColor(for: sample.hitTile, theme: theme).opacity(distanceShade * axisShade * lightShade)
                context.fill(Path(rect), with: .color(wallColor))
            }

            let darkPass = 1.0 - (distanceShade * axisShade * lightShade)
            if darkPass > 0.02 {
                context.fill(
                    Path(rect),
                    with: .color(Color.black.opacity(min(0.82, max(0.0, darkPass * 0.88))))
                )
            }

            if lightShade < 0.65 {
                let darkness = (0.65 - lightShade) * 0.55
                context.fill(Path(rect), with: .color(Color.black.opacity(darkness)))
            }

            if depthTextureAtlas == nil, sample.column.isMultiple(of: 3) {
                let stripe = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: max(1, rect.width * 0.34),
                    height: rect.height
                )
                context.fill(Path(stripe), with: .color(Color.black.opacity(0.08)))
            }

            let topEdge = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1))
            context.fill(topEdge, with: .color(theme.roomHighlight.opacity(0.12)))

            let fogAmount = max(0.0, min(0.72, ((sample.correctedDistance / sample.maxDistance) - 0.40) * 1.25))
            if fogAmount > 0.01 {
                let fog = scene.depth?.usesSkyBackdrop ?? true
                    ? theme.roomShadow.opacity(0.24 + (fogAmount * 0.2))
                    : Color.black.opacity(0.34 + (fogAmount * 0.26))
                context.fill(Path(rect), with: .color(fog.opacity(fogAmount)))
            }
        }
    }

    private func drawDepthBillboards(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        guard !samples.isEmpty else { return }

        let zBuffer = samples.map(\.correctedDistance)
        let billboards = scene.depth?.billboards ?? []
        let horizon = size.height * 0.5
        let columnWidth = size.width / CGFloat(samples.count)

        let sceneDepth = scene.depth
        let fieldOfView = sceneDepth?.fieldOfView ?? depthFieldOfView
        for billboard in billboards {
            let screenCenter = ((billboard.angleOffset / fieldOfView) + 0.5) * size.width
            let projectedHeight = min(
                size.height * 0.88,
                CGFloat((size.height * billboard.scale) / max(0.16, billboard.distance))
            )
            let pattern = depthBillboardPattern(for: billboard.kind)
            let aspect = CGFloat(max(1, pattern.first?.count ?? 1)) / CGFloat(max(1, pattern.count))
            let projectedWidth = max(10, projectedHeight * aspect * billboard.widthScale)
            let left = screenCenter - (projectedWidth / 2)
            let top = horizon - (projectedHeight * 0.5)
            let cellWidth = projectedWidth / CGFloat(max(1, pattern.first?.count ?? 1))
            let cellHeight = projectedHeight / CGFloat(max(1, pattern.count))
            let lightShade = max(0.18, min(1.0, billboard.lightLevel))
            let shade = max(0.28, 1.0 - ((billboard.distance / billboard.maxDistance) * 0.72)) * lightShade
            let color = depthBillboardColor(for: billboard.kind).opacity(shade)
            let shadowRect = CGRect(
                x: left + (projectedWidth * 0.14),
                y: min(size.height - 2, top + projectedHeight - max(2, projectedHeight * 0.08)),
                width: projectedWidth * 0.72,
                height: max(2, projectedHeight * 0.08)
            )
            context.fill(
                Path(ellipseIn: shadowRect),
                with: .color(Color.black.opacity(max(0.08, 0.32 - (lightShade * 0.24))))
            )

            for patternColumn in 0..<max(1, pattern.first?.count ?? 1) {
                let stripeMinX = left + (CGFloat(patternColumn) * cellWidth)
                let stripeMaxX = stripeMinX + cellWidth
                let startSample = max(0, Int(floor(stripeMinX / columnWidth)))
                let endSample = min(samples.count - 1, Int(floor(max(stripeMinX, stripeMaxX - 1) / columnWidth)))
                if startSample > endSample {
                    continue
                }

                var visible = false
                for sampleIndex in startSample...endSample where billboard.distance <= (zBuffer[sampleIndex] + 0.06) {
                    visible = true
                    break
                }
                if !visible {
                    continue
                }

                for patternRow in 0..<pattern.count where pattern[patternRow][patternColumn] == 1 {
                    let rect = CGRect(
                        x: stripeMinX,
                        y: top + (CGFloat(patternRow) * cellHeight),
                        width: max(1, cellWidth),
                        height: max(1, cellHeight)
                    )
                    context.fill(Path(rect), with: .color(color))

                    if patternColumn == 0 || patternColumn == (pattern.first?.count ?? 1) - 1 {
                        let edge = CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
                        context.fill(Path(edge), with: .color(Color.black.opacity(0.18)))
                    }
                }
            }

            let fogAmount = max(0.0, min(0.66, ((billboard.distance / billboard.maxDistance) - 0.46) * 1.45))
            if fogAmount > 0.01 {
                let fogRect = CGRect(
                    x: left,
                    y: top,
                    width: projectedWidth,
                    height: projectedHeight
                )
                let fogColor = scene.depth?.usesSkyBackdrop ?? true
                    ? theme.roomShadow.opacity(0.36)
                    : Color.black.opacity(0.44)
                context.fill(Path(fogRect), with: .color(fogColor.opacity(fogAmount)))
            }
        }
    }

    private func drawDepthReticleGlow(
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        let glow = CGRect(
            x: (size.width * 0.5) - 3,
            y: (size.height * 0.5) - 3,
            width: 6,
            height: 6
        )
        context.fill(Path(ellipseIn: glow), with: .color(palette.lightGold.opacity(0.05)))
    }

    private func depthBillboards(maxDistance: Double) -> [DepthBillboard] {
        guard let map = state.world.maps[state.player.currentMapID] else { return [] }

        let playerCenter = CGPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let forward = facingUnitVector
        let right = rightUnitVector
        var billboards: [DepthBillboard] = []

        for y in 0..<map.lines.count {
            let line = Array(map.lines[y])
            for x in 0..<line.count {
                let position = Position(x: x, y: y)
                if position == state.player.position {
                    continue
                }

                let worldX = Double(x) + 0.5
                let worldY = Double(y) + 0.5
                let dx = worldX - playerCenter.x
                let dy = worldY - playerCenter.y
                let forwardDistance = (dx * forward.x) + (dy * forward.y)
                if forwardDistance <= 0.05 {
                    continue
                }

                let sideDistance = (dx * right.x) + (dy * right.y)
                let distance = hypot(dx, dy)
                if distance > maxDistance {
                    continue
                }

                let angleOffset = atan2(sideDistance, forwardDistance)
                if abs(angleOffset) > (depthFieldOfView * 0.65) {
                    continue
                }

                if let billboard = depthBillboard(at: position, distance: distance, angleOffset: angleOffset, maxDistance: maxDistance) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
    }

    private func depthBillboard(
        at position: Position,
        distance: Double,
        angleOffset: Double,
        maxDistance: Double
    ) -> DepthBillboard? {
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return DepthBillboard(
                id: "enemy:\(enemy.id):\(position.x):\(position.y)",
                pattern: firstPersonEnemyPattern(for: enemy.id),
                color: firstPersonEnemyColor(for: enemy.id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.78,
                widthScale: 0.70
            )
        }

        if let npc = state.world.npcs.first(where: {
            $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return DepthBillboard(
                id: "npc:\(npc.id):\(position.x):\(position.y)",
                pattern: firstPersonNPCPattern(for: npc.id),
                color: firstPersonNPCColor(for: npc.id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.72,
                widthScale: 0.68
            )
        }

        let feature = feature(at: position)
        guard feature != .none else { return nil }
        guard let appearance = depthFeatureAppearance(for: feature) else { return nil }
        return DepthBillboard(
            id: "feature:\(position.x):\(position.y):\(feature.debugName)",
            pattern: appearance.pattern,
            color: appearance.color,
            distance: distance,
            angleOffset: angleOffset,
            maxDistance: maxDistance,
            scale: appearance.scale,
            widthScale: appearance.widthScale
        )
    }

    private func depthFeatureAppearance(for feature: MapFeature) -> (pattern: [[Int]], color: Color, scale: Double, widthScale: CGFloat)? {
        let fallback: (pattern: [[Int]], color: Color, scale: Double, widthScale: CGFloat)?
        switch feature {
        case .none:
            fallback = nil
        case .chest:
            fallback = (
                [
                    [1,1,1],
                    [1,0,1]
                ],
                palette.lightGold,
                0.44,
                0.84
            )
        case .bed:
            fallback = (
                [
                    [1,1,1],
                    [1,0,0]
                ],
                palette.text,
                0.34,
                1.10
            )
        case .plateUp:
            fallback = (
                [
                    [1,1],
                    [1,1]
                ],
                palette.accentViolet,
                0.22,
                1.30
            )
        case .plateDown:
            fallback = (
                [
                    [1,1]
                ],
                palette.text.opacity(0.65),
                0.16,
                1.45
            )
        case .switchIdle:
            fallback = (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                palette.accentBlue,
                0.28,
                0.84
            )
        case .switchLit:
            fallback = (
                [
                    [1,1,1],
                    [1,1,1],
                    [1,1,1]
                ],
                palette.lightGold,
                0.28,
                0.84
            )
        case .torchFloor:
            fallback = (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0],
                    [0,1,0]
                ],
                palette.titleGold,
                0.36,
                0.82
            )
        case .torchWall:
            fallback = (
                [
                    [1,1,1],
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                palette.lightGold,
                0.42,
                0.76
            )
        case .shrine:
            fallback = (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                regionTheme.shrine,
                0.46,
                0.90
            )
        case .beacon:
            fallback = (
                [
                    [0,1,0],
                    [1,1,1],
                    [1,1,1]
                ],
                regionTheme.beacon,
                0.54,
                0.92
            )
        case .gate:
            fallback = (
                [
                    [1,0,1],
                    [1,0,1],
                    [1,1,1]
                ],
                regionTheme.doorLocked,
                0.62,
                1.05
            )
        }

        guard let fallback else {
            return nil
        }

        if let override = GraphicsAssetCatalog.featureSprite(for: feature.debugName) {
            let pattern = override.pattern?.rows ?? fallback.pattern
            let color = override.color.map(Self.swiftUIColor(from:)) ?? fallback.color
            return (pattern, color, fallback.scale, fallback.widthScale)
        }
        return fallback
    }

    private func depthBillboardPattern(for kind: DepthBillboardKind) -> [[Int]] {
        switch kind {
        case .npc(let id):
            return firstPersonNPCPattern(for: id)
        case .enemy(let id):
            return firstPersonEnemyPattern(for: id)
        case .boss(let id):
            return GraphicsAssetCatalog.occupantSprite(for: "boss")?.pattern?.rows
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows
                ?? [
                    [1,0,1],
                    [1,1,1],
                    [1,1,1]
                ]
        case .feature(let feature):
            return depthFeatureAppearance(for: feature)?.pattern ?? [[1]]
        case .tile(let tileType):
            return depthTileAppearance(for: tileType).pattern
        }
    }

    private func depthBillboardColor(for kind: DepthBillboardKind) -> Color {
        switch kind {
        case .npc(let id):
            return firstPersonNPCColor(for: id)
        case .enemy(let id):
            return firstPersonEnemyColor(for: id)
        case .boss(let id):
            return GraphicsAssetCatalog.occupantSprite(for: "boss")?.color.map(Self.swiftUIColor(from:))
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.color.map(Self.swiftUIColor(from:))
                ?? palette.accentViolet
        case .feature(let feature):
            return depthFeatureAppearance(for: feature)?.color ?? palette.text
        case .tile(let tileType):
            return depthTileAppearance(for: tileType).color
        }
    }

    private func depthTileAppearance(for tileType: TileType) -> (pattern: [[Int]], color: Color) {
        switch tileType {
        case .stairs:
            return (
                [
                    [1,1,1,1],
                    [1,0,0,0],
                    [1,1,1,0]
                ],
                regionTheme.stairs
            )
        case .doorOpen:
            return (
                [
                    [1,0,1],
                    [1,0,1],
                    [1,1,1]
                ],
                regionTheme.doorOpen
            )
        case .brush:
            return (
                [
                    [1,0,1,0],
                    [0,1,0,1],
                    [1,0,1,0]
                ],
                regionTheme.brush
            )
        case .shrine:
            return (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                regionTheme.shrine
            )
        case .beacon:
            return (
                [
                    [0,1,0],
                    [1,1,1],
                    [1,1,1]
                ],
                regionTheme.beacon
            )
        case .floor, .wall, .water, .doorLocked:
            return (
                [
                    [1]
                ],
                palette.text
            )
        }
    }

    private var depthFieldOfView: Double {
        .pi / 3.1
    }

    private var facingUnitVector: (x: Double, y: Double) {
        switch state.player.facing {
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

    private var rightUnitVector: (x: Double, y: Double) {
        switch state.player.facing {
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

    private var usesSkyBackdrop: Bool {
        let mapID = state.player.currentMapID
        let indoorFragments = [
            "barrow",
            "spire",
            "vault",
            "archive",
            "observatory",
            "cloister",
            "keep",
            "catacomb",
            "crypt",
            "sanctum"
        ]
        return indoorFragments.allSatisfy { !mapID.contains($0) }
    }

    private func corridorLayer(for slice: CorridorSlice, in size: CGSize, theme: RegionTheme) -> some View {
        let near = perspectiveFrame(depth: slice.depth, in: size)
        let far = perspectiveFrame(depth: slice.depth + 1, in: size)

        return ZStack {
            quad(
                near.bottomLeft,
                near.bottomRight,
                far.bottomRight,
                far.bottomLeft
            )
            .fill(theme.floor.opacity(0.24 + (Double(slice.depth) * 0.08)))

            quad(
                near.topLeft,
                near.topRight,
                far.topRight,
                far.topLeft
            )
            .fill(Color.white.opacity(0.015 + (Double(slice.depth) * 0.01)))

            if slice.leftBlocked {
                quad(
                    near.topLeft,
                    far.topLeft,
                    far.bottomLeft,
                    near.bottomLeft
                )
                .fill(sideWallColor(for: slice.leftTile, theme: theme, brightness: 0.90 - (Double(slice.depth) * 0.12)))
            } else {
                corridorGuide(from: near.topLeft, to: far.topLeft, intensity: 0.32)
                corridorGuide(from: near.bottomLeft, to: far.bottomLeft, intensity: 0.22)
            }

            if slice.rightBlocked {
                quad(
                    near.topRight,
                    far.topRight,
                    far.bottomRight,
                    near.bottomRight
                )
                .fill(sideWallColor(for: slice.rightTile, theme: theme, brightness: 1.0 - (Double(slice.depth) * 0.12)))
            } else {
                corridorGuide(from: near.topRight, to: far.topRight, intensity: 0.32)
                corridorGuide(from: near.bottomRight, to: far.bottomRight, intensity: 0.22)
            }

            if slice.frontBlocked {
                Rectangle()
                    .fill(frontWallColor(for: slice.frontTile, theme: theme))
                    .frame(width: far.width, height: far.height)
                    .position(x: far.center.x, y: far.center.y)
                    .overlay(
                        Rectangle()
                            .stroke(theme.roomHighlight.opacity(0.48), lineWidth: 2)
                            .frame(width: far.width, height: far.height)
                            .position(x: far.center.x, y: far.center.y)
                    )
            } else {
                Rectangle()
                    .stroke(theme.roomHighlight.opacity(0.18), lineWidth: 1)
                    .frame(width: far.width, height: far.height)
                    .position(x: far.center.x, y: far.center.y)
            }

            if let feature = firstPersonFeature(for: slice.feature, theme: theme, in: far) {
                feature
            }

            if let sprite = firstPersonOccupant(for: slice.occupant, in: far) {
                sprite
            }
        }
    }

    private func firstPersonFeature(for feature: MapFeature, theme _: RegionTheme, in frame: PerspectiveFrame) -> AnyView? {
        guard let appearance = depthFeatureAppearance(for: feature) else {
            return nil
        }

        let spriteHeight = max(12, frame.height * 0.34)
        let spriteWidth = max(12, frame.width * 0.18)
        let view = PixelSprite(color: appearance.color, pattern: appearance.pattern)
            .frame(width: spriteWidth, height: spriteHeight)
            .position(x: frame.center.x, y: frame.bottomLeft.y - (spriteHeight * 0.55))
        return AnyView(view)
    }

    private func firstPersonOccupant(for occupant: MapOccupant, in frame: PerspectiveFrame) -> AnyView? {
        let color: Color
        let pattern: [[Int]]

        switch occupant {
        case .none:
            return nil
        case .player:
            color = GraphicsAssetCatalog.occupantSprite(for: "player")?.color.map(Self.swiftUIColor(from:)) ?? palette.text
            pattern = GraphicsAssetCatalog.occupantSprite(for: "player")?.pattern?.rows ?? [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case .npc(let id):
            color = firstPersonNPCColor(for: id)
            pattern = firstPersonNPCPattern(for: id)
        case .enemy(let id):
            color = firstPersonEnemyColor(for: id)
            pattern = firstPersonEnemyPattern(for: id)
        case .boss(let id):
            color = GraphicsAssetCatalog.occupantSprite(for: "boss")?.color.map(Self.swiftUIColor(from:))
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.color.map(Self.swiftUIColor(from:))
                ?? palette.accentViolet
            pattern = GraphicsAssetCatalog.occupantSprite(for: "boss")?.pattern?.rows
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows
                ?? [
                    [1,0,1],
                    [1,1,1],
                    [1,1,1]
                ]
        }

        let spriteHeight = max(18, frame.height * 0.62)
        let spriteWidth = max(18, frame.width * 0.34)
        let view = ZStack {
            PixelSprite(color: Color.black.opacity(0.42), pattern: pattern)
                .offset(x: spriteWidth * 0.04, y: spriteHeight * 0.04)
            PixelSprite(color: color, pattern: pattern)
        }
        .frame(width: spriteWidth, height: spriteHeight)
        .position(x: frame.center.x, y: frame.bottomLeft.y - (spriteHeight * 0.38))
        return AnyView(view)
    }

    private func corridorGuide(from start: CGPoint, to end: CGPoint, intensity: Double) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(palette.text.opacity(intensity), lineWidth: 1)
    }

    private func perspectiveFrame(depth: Int, in size: CGSize) -> PerspectiveFrame {
        let factors: [CGFloat] = [0.04, 0.14, 0.26, 0.36, 0.44]
        let safeDepth = max(0, min(depth, factors.count - 1))
        let inset = min(size.width, size.height) * factors[safeDepth]
        let horizontal = inset * 1.22
        let vertical = inset * 0.82
        let left = horizontal
        let right = size.width - horizontal
        let top = vertical
        let bottom = size.height - vertical
        return PerspectiveFrame(
            topLeft: CGPoint(x: left, y: top),
            topRight: CGPoint(x: right, y: top),
            bottomLeft: CGPoint(x: left, y: bottom),
            bottomRight: CGPoint(x: right, y: bottom)
        )
    }

    private func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.addLine(to: d)
            path.closeSubpath()
        }
    }

    private func corridorSlices(maxDepth: Int = 4) -> [CorridorSlice] {
        var slices: [CorridorSlice] = []
        guard state.world.maps[state.player.currentMapID] != nil else { return slices }

        for depth in 0..<maxDepth {
            let frontPosition = advancedPosition(from: state.player.position, direction: state.player.facing, steps: depth + 1)
            let frontTile = tile(at: frontPosition)
            let leftTile = tile(at: advancedPosition(from: frontPosition, direction: state.player.facing.leftTurn, steps: 1))
            let rightTile = tile(at: advancedPosition(from: frontPosition, direction: state.player.facing.rightTurn, steps: 1))
            let slice = CorridorSlice(
                depth: depth,
                frontTile: frontTile,
                leftTile: leftTile,
                rightTile: rightTile,
                leftBlocked: !leftTile.walkable,
                rightBlocked: !rightTile.walkable,
                frontBlocked: !frontTile.walkable,
                occupant: occupant(at: frontPosition),
                feature: feature(at: frontPosition)
            )
            slices.append(slice)
            if slice.frontBlocked {
                break
            }
        }

        return slices
    }

    private func facingUnitVector(for direction: Direction) -> (x: Double, y: Double) {
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

    private func rightUnitVector(for direction: Direction) -> (x: Double, y: Double) {
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

    private func lightValueString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func fract(_ value: Double) -> CGFloat {
        CGFloat(value - floor(value))
    }

    private func advancedPosition(from start: Position, direction: Direction, steps: Int) -> Position {
        Position(
            x: start.x + (direction.delta.x * steps),
            y: start.y + (direction.delta.y * steps)
        )
    }

    private func tile(at position: Position) -> Tile {
        guard let map = state.world.maps[state.player.currentMapID],
              position.y >= 0,
              position.y < map.lines.count,
              position.x >= 0,
              position.x < map.lines[position.y].count else {
            return TileFactory.tile(for: "#")
        }

        let raw = Array(map.lines[position.y])[position.x]
        return TileFactory.tile(for: resolved(raw))
    }

    private func sideWallColor(for tile: Tile, theme: RegionTheme, brightness: Double) -> Color {
        frontWallColor(for: tile, theme: theme).opacity(max(0.28, brightness))
    }

    private func frontWallColor(for tile: Tile, theme: RegionTheme) -> Color {
        switch tile.type {
        case .floor:
            return theme.floor
        case .wall:
            return theme.wall
        case .water:
            return theme.water
        case .brush:
            return theme.brush
        case .doorLocked:
            return theme.doorLocked
        case .doorOpen:
            return theme.doorOpen
        case .shrine:
            return theme.shrine
        case .stairs:
            return theme.stairs
        case .beacon:
            return theme.beacon
        }
    }

    private func firstPersonNPCPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.npcSprite(for: id)?.pattern?.rows {
            return pattern
        }
        switch id {
        case "elder":
            return [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1],
                [0,1,0],
                [0,1,0]
            ]
        case "orchard_guide":
            return [
                [0,1,0],
                [1,1,0],
                [0,1,1]
            ]
        default:
            return [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        }
    }

    private func firstPersonNPCColor(for id: String) -> Color {
        if let color = GraphicsAssetCatalog.npcSprite(for: id)?.color {
            return Self.swiftUIColor(from: color)
        }
        switch id {
        case "elder":
            return palette.accentBlue
        case "field_scout":
            return palette.text
        case "orchard_guide":
            return palette.accentGreen
        case "barrow_scholar":
            return palette.accentViolet
        default:
            return palette.lightGold
        }
    }

    private func firstPersonEnemyPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows {
            return pattern
        }
        if id.hasPrefix("crow") {
            return [
                [1,0,1],
                [1,1,1],
                [0,1,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,1,0],
                [1,1,1],
                [0,1,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        }
        return [
            [1,1,1],
            [1,0,1],
            [1,1,1]
        ]
    }

    private func firstPersonEnemyColor(for id: String) -> Color {
        if let color = GraphicsAssetCatalog.enemySprite(for: id)?.color {
            return Self.swiftUIColor(from: color)
        }
        if id.hasPrefix("crow") {
            return palette.titleGold
        }
        if id.hasPrefix("hound") {
            return palette.accentGreen
        }
        if id.hasPrefix("wraith") {
            return palette.accentViolet
        }
        return palette.titleGold
    }

    private func resolved(_ raw: Character) -> Character {
        if raw == "+", state.quests.has(.barrowUnlocked) {
            return "/"
        }
        return raw
    }

    private func occupant(at position: Position) -> MapOccupant {
        if state.player.position == position {
            return .player
        }
        if let npc = state.world.npcs.first(where: { $0.mapID == state.player.currentMapID && $0.position == position }) {
            return .npc(npc.id)
        }
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return enemy.ai == .boss ? .boss(enemy.id) : .enemy(enemy.id)
        }
        return .none
    }

    private func feature(at position: Position) -> MapFeature {
        guard let interactable = state.world.maps[state.player.currentMapID]?.interactables.first(where: { $0.position == position }) else {
            return .none
        }
        switch interactable.kind {
        case .chest:
            return state.world.openedInteractables.contains(interactable.id) ? .none : .chest
        case .bed:
            return .bed
        case .plate:
            return state.world.openedInteractables.contains(interactable.id) ? .plateDown : .plateUp
        case .switchRune:
            return state.world.openedInteractables.contains("spire_mirrors_aligned") ? .switchLit : .switchIdle
        case .torchFloor:
            return .torchFloor
        case .torchWall:
            return .torchWall
        case .shrine:
            return .shrine
        case .beacon:
            return .beacon
        case .gate:
            return .gate
        case .npc:
            return .none
        }
    }

    private var regionTheme: RegionTheme {
        let base: RegionTheme
        switch scene.currentMapID {
        case "merrow_village":
            base = RegionTheme(
                floor: Color(red: 0.18, green: 0.11, blue: 0.08),
                wall: Color(red: 0.46, green: 0.23, blue: 0.12),
                water: palette.accentBlue,
                brush: Color(red: 0.27, green: 0.58, blue: 0.17),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: palette.earth,
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.95, green: 0.56, blue: 0.07),
                roomHighlight: palette.lightGold,
                roomShadow: Color.black.opacity(0.55),
                pattern: .brick
            )
        case "south_fields":
            base = RegionTheme(
                floor: Color(red: 0.31, green: 0.18, blue: 0.06),
                wall: Color(red: 0.44, green: 0.35, blue: 0.11),
                water: palette.accentBlue,
                brush: Color(red: 0.32, green: 0.74, blue: 0.17),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.56, green: 0.40, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.90, green: 0.64, blue: 0.09),
                roomHighlight: Color(red: 0.98, green: 0.84, blue: 0.37),
                roomShadow: Color.black.opacity(0.55),
                pattern: .speckle
            )
        case "sunken_orchard":
            base = RegionTheme(
                floor: Color(red: 0.21, green: 0.15, blue: 0.05),
                wall: Color(red: 0.36, green: 0.41, blue: 0.12),
                water: Color(red: 0.18, green: 0.46, blue: 0.75),
                brush: Color(red: 0.22, green: 0.58, blue: 0.13),
                doorLocked: Color(red: 0.78, green: 0.56, blue: 0.12),
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.44, green: 0.32, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.29, green: 0.74, blue: 0.24),
                roomHighlight: Color(red: 0.78, green: 0.92, blue: 0.36),
                roomShadow: Color.black.opacity(0.55),
                pattern: .weave
            )
        case "hollow_barrows":
            base = RegionTheme(
                floor: Color(red: 0.14, green: 0.10, blue: 0.10),
                wall: Color(red: 0.50, green: 0.48, blue: 0.44),
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: Color(red: 0.78, green: 0.49, blue: 0.15),
                doorOpen: palette.lightGold,
                shrine: Color(red: 0.58, green: 0.38, blue: 0.80),
                stairs: Color(red: 0.48, green: 0.34, blue: 0.22),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.85, green: 0.85, blue: 0.78),
                roomHighlight: Color(red: 0.98, green: 0.96, blue: 0.86),
                roomShadow: Color.black.opacity(0.60),
                pattern: .hash
            )
        case "black_fen":
            base = RegionTheme(
                floor: Color(red: 0.09, green: 0.14, blue: 0.08),
                wall: Color(red: 0.27, green: 0.36, blue: 0.16),
                water: Color(red: 0.17, green: 0.43, blue: 0.60),
                brush: Color(red: 0.33, green: 0.47, blue: 0.08),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.31, green: 0.25, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.33, green: 0.68, blue: 0.22),
                roomHighlight: Color(red: 0.73, green: 0.88, blue: 0.31),
                roomShadow: Color.black.opacity(0.62),
                pattern: .mire
            )
        case "beacon_spire":
            base = RegionTheme(
                floor: Color(red: 0.10, green: 0.10, blue: 0.18),
                wall: Color(red: 0.43, green: 0.43, blue: 0.58),
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.42, green: 0.30, blue: 0.15),
                beacon: Color(red: 0.98, green: 0.92, blue: 0.32),
                roomBorder: Color(red: 0.28, green: 0.63, blue: 0.88),
                roomHighlight: Color(red: 0.89, green: 0.92, blue: 0.99),
                roomShadow: Color.black.opacity(0.64),
                pattern: .circuit
            )
        default:
            base = RegionTheme(
                floor: palette.ground,
                wall: palette.stone,
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: palette.earth,
                beacon: palette.lightGold,
                roomBorder: palette.titleGold,
                roomHighlight: palette.lightGold,
                roomShadow: Color.black.opacity(0.55),
                pattern: .brick
            )
        }
        return applyMapThemeOverride(base: base, mapID: scene.currentMapID)
    }

    private func applyMapThemeOverride(base: RegionTheme, mapID: String) -> RegionTheme {
        guard let override = GraphicsAssetCatalog.mapTheme(for: mapID) else {
            return base
        }

        return RegionTheme(
            floor: override.floor.map(Self.swiftUIColor(from:)) ?? base.floor,
            wall: override.wall.map(Self.swiftUIColor(from:)) ?? base.wall,
            water: override.water.map(Self.swiftUIColor(from:)) ?? base.water,
            brush: override.brush.map(Self.swiftUIColor(from:)) ?? base.brush,
            doorLocked: override.doorLocked.map(Self.swiftUIColor(from:)) ?? base.doorLocked,
            doorOpen: override.doorOpen.map(Self.swiftUIColor(from:)) ?? base.doorOpen,
            shrine: override.shrine.map(Self.swiftUIColor(from:)) ?? base.shrine,
            stairs: override.stairs.map(Self.swiftUIColor(from:)) ?? base.stairs,
            beacon: override.beacon.map(Self.swiftUIColor(from:)) ?? base.beacon,
            roomBorder: override.roomBorder.map(Self.swiftUIColor(from:)) ?? base.roomBorder,
            roomHighlight: override.roomHighlight.map(Self.swiftUIColor(from:)) ?? base.roomHighlight,
            roomShadow: override.roomShadow.map(Self.swiftUIColor(from:)) ?? base.roomShadow,
            pattern: override.pattern.map(Self.chamberPattern(from:)) ?? base.pattern
        )
    }

    private static func swiftUIColor(from color: GraphicsRGBColor) -> Color {
        Color(
            red: Double(color.r) / 255.0,
            green: Double(color.g) / 255.0,
            blue: Double(color.b) / 255.0
        )
    }

    private static func chamberPattern(from pattern: GraphicsFloorPatternName) -> ChamberPattern {
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
}
#endif
