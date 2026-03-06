#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

struct DepthTextureAtlas {
    let tileSize: CGFloat
    let columns: Int
    let floorColors: [CGColor]
    let wallSlices: [TileType: [CGImage]]

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
        let clampedU = max(0.0, min(0.999, u))
        guard let slices = wallSlices[tileType], !slices.isEmpty else {
            return nil
        }
        let index = min(slices.count - 1, Int(floor(clampedU * Double(slices.count))))
        return slices[index]
    }

    func floorColor(u: CGFloat, v: CGFloat) -> CGColor? {
        guard !floorColors.isEmpty else {
            return nil
        }
        let clampedU = max(0.0, min(0.999, u))
        let clampedV = max(0.0, min(0.999, v))
        let pixelX = min(Int(tileSize) - 1, Int(floor(clampedU * tileSize)))
        let pixelY = min(Int(tileSize) - 1, Int(floor(clampedV * tileSize)))
        let index = (pixelY * Int(tileSize)) + pixelX
        return floorColors[index]
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

        let tileSize: CGFloat = 16
        let textureWidth = CGFloat(cgImage.width)
        let columns = Int(textureWidth / tileSize)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let floorRect = CGRect(
            x: tileSize * 4,
            y: 0,
            width: tileSize,
            height: tileSize
        )
        let floorColors = makeFloorColors(bitmap: bitmap, rect: floorRect)
        let wallSlices = makeWallSlices(cgImage: cgImage, tileSize: tileSize, columns: columns)

        return DepthTextureAtlas(
            tileSize: tileSize,
            columns: columns,
            floorColors: floorColors,
            wallSlices: wallSlices
        )
    }

    private static func makeFloorColors(bitmap: NSBitmapImageRep, rect: CGRect) -> [CGColor] {
        let minX = Int(rect.minX)
        let minY = Int(rect.minY)
        let width = Int(rect.width)
        let height = Int(rect.height)
        var colors: [CGColor] = []
        colors.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let color = bitmap.colorAt(x: minX + x, y: minY + y)?.cgColor ?? NSColor.black.cgColor
                colors.append(color)
            }
        }

        return colors
    }

    private static func makeWallSlices(
        cgImage: CGImage,
        tileSize: CGFloat,
        columns: Int
    ) -> [TileType: [CGImage]] {
        let atlas = DepthTextureAtlas(
            tileSize: tileSize,
            columns: columns,
            floorColors: [],
            wallSlices: [:]
        )
        let tileTypes: [TileType] = [
            .floor,
            .wall,
            .water,
            .brush,
            .doorLocked,
            .doorOpen,
            .shrine,
            .stairs,
            .beacon
        ]
        var slicesByTile: [TileType: [CGImage]] = [:]

        for tileType in tileTypes {
            let rect = atlas.wallRect(for: tileType)
            let y = Int(rect.minY)
            let height = Int(rect.height)
            let sliceCount = max(1, Int(rect.width))
            var slices: [CGImage] = []
            slices.reserveCapacity(sliceCount)

            for column in 0..<sliceCount {
                let x = Int(rect.minX) + column
                let crop = CGRect(x: x, y: y, width: 1, height: height)
                if let slice = cgImage.cropping(to: crop) {
                    slices.append(slice)
                }
            }

            slicesByTile[tileType] = slices
        }

        return slicesByTile
    }
}

extension MapBoardView {
    func firstPersonView(theme: RegionTheme) -> some View {
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
            Text("BACKDROP \(scene.depth?.backdropLabel ?? "SKY")")
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
                        if cell.tile.type.blocksDepthLighting {
                            color = Color(
                                red: 0.10 + (normalized * 0.32),
                                green: 0.10 + (normalized * 0.28),
                                blue: 0.12 + (normalized * 0.24)
                            )
                        } else if cell.tile.type.usesDepthPoolSurface {
                            color = Color(
                                red: 0.10 + (normalized * 0.20),
                                green: 0.16 + (normalized * 0.32),
                                blue: 0.24 + (normalized * 0.52)
                            )
                        }
                        context.fill(Path(rect), with: .color(color))

                        if cell.tile.type.blocksDepthLighting {
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
        drawDepthBackdrop(into: &context, size: size, samples: samples, theme: theme)
        drawDepthWalls(into: &context, size: size, samples: samples, theme: theme)
        drawDepthBillboards(into: &context, size: size, samples: samples, theme: theme)
        drawDepthReticleGlow(into: &context, size: size)
    }

    private func drawDepthBackdrop(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
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
        let hasSkyBackdrop = scene.depth?.usesSkyBackdrop ?? true
        let playerX = Double(scene.player.position.x) + 0.5
        let playerY = Double(scene.player.position.y) + 0.5
        let skyGlow = min(0.22, max(0.04, (worldLighting?.ambient ?? 0.18) * 0.45))
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
        let effectiveFloorBands = max(floorBands, (floorLighting?.bands ?? 20) + 2)
        let projections = depthFloorProjection(
            size: size,
            horizon: horizon,
            floorBands: effectiveFloorBands,
            fieldOfView: fieldOfView,
            facing: facing
        )

        if hasSkyBackdrop {
            context.fill(
                Path(ceilingRect),
                with: .linearGradient(
                    Gradient(colors: [
                        theme.roomHighlight.opacity(0.30 + skyGlow),
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

            if let worldLighting {
                drawCeilingShadowBands(
                    into: &context,
                    projections: projections,
                    horizon: horizon,
                    floorLighting: floorLighting,
                    worldLighting: worldLighting,
                    playerX: playerX,
                    playerY: playerY,
                    theme: theme
                )
            }
        }

        context.fill(Path(floorRect), with: .color(theme.floor.opacity(0.18)))

        for (band, projection) in projections.enumerated() {
            let y0 = CGFloat(projection.y0)
            let y1 = CGFloat(projection.y1)
            let t1 = CGFloat(band + 1) / CGFloat(max(1, effectiveFloorBands))
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
                    projection: projection,
                    theme: theme
                )
                context.fill(Path(rect), with: .color(Color.black.opacity(0.06 + (Double(t1) * 0.10))))
                context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe.opacity(0.16)))
            } else {
                context.fill(Path(rect), with: .color(theme.floor.opacity(shade)))
                context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe))
            }

            if band > 0 {
                let line = Path(CGRect(x: 0, y: y0, width: size.width, height: 1))
                context.fill(line, with: .color(theme.roomHighlight.opacity(0.03)))
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
        projection: DepthFloorBandProjection,
        theme: RegionTheme
    ) {
        let playerX = Double(scene.player.position.x) + 0.5
        let playerY = Double(scene.player.position.y) + 0.5
        let rowDistance = projection.rowDistance
        let bandNorm = projection.bandNorm
        let stripCount = projection.strips.count
        guard stripCount > 0 else { return }
        var stripLightLevels = Array(repeating: floorLighting?.ambient ?? worldLighting?.ambient ?? 0.20, count: stripCount)
        var stripShadowLevels = Array(repeating: 0.0, count: stripCount)
        var waterSurfaces: [(pit: CGRect, surface: CGRect, shimmer: Double)] = []

        context.withCGContext { cgContext in
            cgContext.interpolationQuality = .none
            for (index, strip) in projection.strips.enumerated() {
                let xNorm = strip.xNormalized
                let rayX = strip.rayX
                let rayY = strip.rayY
                let worldX = playerX + (rowDistance * rayX)
                let worldY = playerY + (rowDistance * rayY)
                let u = fract(worldX)
                let v = fract(worldY)

                let stripe = CGRect(
                    x: CGFloat(strip.x0),
                    y: rect.minY,
                    width: max(1, CGFloat(strip.x1 - strip.x0)),
                    height: rect.height
                )
                if let color = atlas.floorColor(u: u, v: v) {
                    cgContext.setFillColor(color)
                    cgContext.fill(stripe)
                }

                let sampledTile = tile(at: Position(x: Int(floor(worldX)), y: Int(floor(worldY))))
                if sampledTile.type.usesDepthPoolSurface {
                    let poolInset = max(1.0, rect.height * (0.12 + (bandNorm * 0.10)))
                    let waterRect = CGRect(
                        x: stripe.minX,
                        y: min(rect.maxY - 1, stripe.minY + poolInset),
                        width: stripe.width,
                        height: max(1, stripe.height - poolInset)
                    )
                    let shimmer = Double((u * 0.55) + (v * 0.45))
                    waterSurfaces.append((pit: stripe, surface: waterRect, shimmer: shimmer))
                }

                let light = floorLighting?.interpolatedLevel(
                        xNormalized: xNorm,
                        yNormalized: bandNorm
                    )
                    ?? worldLighting?.level(atWorldX: worldX, y: worldY)
                    ?? (floorLighting?.ambient ?? worldLighting?.ambient ?? 0.20)
                stripLightLevels[index] = light
                stripShadowLevels[index] = floorLighting?.interpolatedShadow(
                    xNormalized: xNorm,
                    yNormalized: bandNorm
                )
                ?? worldLighting?.shadowLevel(atWorldX: worldX, y: worldY)
                ?? 0.0
            }
        }

        for water in waterSurfaces {
            context.fill(Path(water.pit), with: .color(theme.floor.opacity(0.46)))
            context.fill(Path(water.surface), with: .color(theme.water.opacity(0.78)))

            let lip = CGRect(
                x: water.surface.minX,
                y: water.surface.minY,
                width: water.surface.width,
                height: max(1, water.surface.height * 0.10)
            )
            context.fill(Path(lip), with: .color(Color.black.opacity(0.18)))

            let shimmerY = water.surface.minY + max(1, water.surface.height * 0.26)
            let shimmerBand = CGRect(
                x: water.surface.minX + max(0, water.surface.width * 0.08),
                y: shimmerY,
                width: max(1, water.surface.width * 0.84),
                height: max(1, water.surface.height * 0.10)
            )
            let shimmerOpacity = 0.08 + (0.10 * (water.shimmer - floor(water.shimmer)))
            context.fill(Path(shimmerBand), with: .color(theme.roomHighlight.opacity(shimmerOpacity)))
        }

        DepthProjectionMath.smoothStripLevels(&stripLightLevels)
        DepthProjectionMath.smoothStripLevels(&stripShadowLevels)

        let ambient = floorLighting?.ambient ?? worldLighting?.ambient
        if let ambient {
            for (index, strip) in projection.strips.enumerated() {
                let stripe = CGRect(
                    x: strip.x0,
                    y: rect.minY,
                    width: max(1, strip.x1 - strip.x0),
                    height: rect.height
                )
                let shadow = stripShadowLevels[index]
                let shaded = max(ambient * 0.10, stripLightLevels[index] - (shadow * 0.74))
                let lift = max(0.0, shaded - ambient)
                let dim = max(max(0.0, ambient - shaded), shadow * 0.40)
                if lift > 0.01 {
                    let glow = theme.roomHighlight.opacity(min(0.44, 0.05 + (lift * 0.60)))
                    context.fill(Path(stripe), with: .color(glow))
                }
                if dim > 0.01 {
                    let shadow = Color.black.opacity(min(0.24, 0.04 + (dim * 0.38)))
                    context.fill(Path(stripe), with: .color(shadow))
                }
                if shadow > 0.01 {
                    let occlusion = Color.black.opacity(min(0.24, shadow * 0.28))
                    context.fill(Path(stripe), with: .color(occlusion))
                }
            }
        }
    }

    private func drawCeilingShadowBands(
        into context: inout GraphicsContext,
        projections: [DepthFloorBandProjection],
        horizon: CGFloat,
        floorLighting: DepthFloorLightingSnapshot?,
        worldLighting: DepthWorldLightingSnapshot,
        playerX: Double,
        playerY: Double,
        theme: RegionTheme
    ) {
        for projection in projections {
            let horizonValue = Double(horizon)
            let mirroredY0 = horizonValue - (projection.y1 - horizonValue)
            let mirroredY1 = horizonValue - (projection.y0 - horizonValue)
            let rect = CGRect(
                x: 0,
                y: max(0, CGFloat(mirroredY0)),
                width: CGFloat(projection.strips.last?.x1 ?? 0),
                height: max(1, CGFloat(mirroredY1 - mirroredY0))
            )
            if rect.height <= 0 {
                continue
            }

            var stripLevels = Array(repeating: worldLighting.ambient, count: projection.strips.count)
            var stripShadowLevels = Array(repeating: 0.0, count: projection.strips.count)
            for (index, strip) in projection.strips.enumerated() {
                let light = floorLighting?.interpolatedLevel(
                    xNormalized: strip.xNormalized,
                    yNormalized: projection.bandNorm
                ) ?? {
                    let worldX = playerX + (projection.rowDistance * strip.rayX)
                    let worldY = playerY + (projection.rowDistance * strip.rayY)
                    return worldLighting.level(atWorldX: worldX, y: worldY)
                }()
                let shadow = floorLighting?.interpolatedShadow(
                    xNormalized: strip.xNormalized,
                    yNormalized: projection.bandNorm
                ) ?? {
                    let worldX = playerX + (projection.rowDistance * strip.rayX)
                    let worldY = playerY + (projection.rowDistance * strip.rayY)
                    return worldLighting.shadowLevel(atWorldX: worldX, y: worldY)
                }()
                let shaded = light - (shadow * 0.72)
                let minimum = max(0.01, worldLighting.ambient * 0.14)
                stripLevels[index] = max(minimum, min(1.0, shaded))
                stripShadowLevels[index] = shadow
            }

            DepthProjectionMath.smoothStripLevels(&stripLevels)
            DepthProjectionMath.smoothStripLevels(&stripShadowLevels)

            for (index, strip) in projection.strips.enumerated() {
                let stripe = CGRect(
                    x: CGFloat(strip.x0),
                    y: rect.minY,
                    width: max(1, CGFloat(strip.x1 - strip.x0)),
                    height: rect.height
                )
                let level = stripLevels[index]
                let shadow = stripShadowLevels[index]
                let dim = max(max(0.0, worldLighting.ambient - level), shadow * 0.46)
                let lift = max(0.0, level - worldLighting.ambient)

                if dim > 0.01 {
                    let darkness = Color.black.opacity(min(0.38, 0.04 + (dim * 0.46)))
                    context.fill(Path(stripe), with: .color(darkness))
                }
                if shadow > 0.01 {
                    let occlusion = Color.black.opacity(min(0.30, shadow * 0.30))
                    context.fill(Path(stripe), with: .color(occlusion))
                }
                if lift > 0.01 {
                    let highlight = theme.roomHighlight.opacity(min(0.18, 0.02 + (lift * 0.22)))
                    context.fill(Path(stripe), with: .color(highlight))
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
            let shadowShade = max(0.0, min(1.0, sample.shadowLevel))
            let effectiveShade = max(0.14, lightShade * (1.0 - (shadowShade * 0.78)))
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
                let wallColor = frontWallColor(for: sample.hitTile, theme: theme).opacity(distanceShade * axisShade * effectiveShade)
                context.fill(Path(rect), with: .color(wallColor))
            }

            let darkPass = 1.0 - (distanceShade * axisShade * effectiveShade)
            if darkPass > 0.02 {
                context.fill(
                    Path(rect),
                    with: .color(Color.black.opacity(min(0.82, max(0.0, darkPass * 0.88))))
                )
            }

            if effectiveShade < 0.65 {
                let darkness = (0.65 - effectiveShade) * 0.55
                context.fill(Path(rect), with: .color(Color.black.opacity(darkness)))
            }
            if shadowShade > 0.01 {
                let shadow = Color.black.opacity(min(0.30, shadowShade * 0.26))
                context.fill(Path(rect), with: .color(shadow))
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
            let pattern = depthBillboardPattern(for: billboard.kind)
            let aspect = CGFloat(max(1, pattern.first?.count ?? 1)) / CGFloat(max(1, pattern.count))
            let projection = DepthProjectionMath.billboardProjection(
                screenWidth: Double(size.width),
                screenHeight: Double(size.height),
                horizon: Double(horizon),
                fieldOfView: fieldOfView,
                billboard: billboard,
                aspectRatio: Double(aspect)
            )
            let projectedHeight = CGFloat(projection.height)
            let projectedWidth = CGFloat(projection.width)
            let left = CGFloat(projection.left)
            let top = CGFloat(projection.top)
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
}
#endif
