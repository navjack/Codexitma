import CSDL3
import Foundation

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

@MainActor
private var cachedDepthFloorProjection: [DepthFloorProjectionCacheKey: [DepthFloorBandProjection]] = [:]

extension SDLGraphicsLauncher {
    static func renderDepth(
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

    static func tileColor(for type: TileType, theme: SDLBoardTheme) -> SDLColor {
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

    static func featureColor(for feature: MapFeature) -> SDLColor {
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

    static func occupantColor(for occupant: MapOccupant) -> SDLColor {
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

    static func editorOverlayColor(for style: EditorCanvasOverlayStyle) -> SDLColor {
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

    static func editorOverlayTextColor(for style: EditorCanvasOverlayStyle) -> SDLColor {
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

    static func drawTileAccent(
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

    static func drawFloorAccent(
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

    static func featurePattern(for feature: MapFeature) -> [[Int]] {
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

    static func occupantPattern(for occupant: MapOccupant) -> [[Int]] {
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
}
