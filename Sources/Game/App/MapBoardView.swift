import AppKit
import Foundation
import SwiftUI

struct MapBoardView: View {
    let state: GameState
    let palette: UltimaPalette
    let visualTheme: GraphicsVisualTheme

    private let cell: CGFloat = 14

    var body: some View {
        if visualTheme == .depth3D {
            firstPersonView(theme: regionTheme)
        } else {
            topDownView(map: state.world.maps[state.player.currentMapID], theme: regionTheme)
        }
    }

    private func topDownView(map: MapDefinition?, theme: RegionTheme) -> some View {
        let boardPadding = visualTheme == .gemstone ? 4.0 : 2.0
        let boardScale = visualTheme == .gemstone ? 2.0 : 1.84
        let boardWidth = CGFloat(map?.lines.first?.count ?? 0) * cell
        let boardHeight = CGFloat(map?.lines.count ?? 0) * cell

        return ZStack(alignment: .topLeading) {
            if visualTheme == .gemstone {
                Rectangle()
                    .fill(theme.roomShadow)
                    .offset(x: 3, y: 3)
            }

            VStack(spacing: 0) {
                ForEach(Array((map?.lines ?? []).enumerated()), id: \.offset) { y, line in
                    HStack(spacing: 0) {
                        ForEach(Array(line.enumerated()), id: \.offset) { x, raw in
                            LowResTileView(
                                tile: TileFactory.tile(for: resolved(raw)),
                                occupant: occupant(at: Position(x: x, y: y)),
                                feature: feature(at: Position(x: x, y: y)),
                                palette: palette,
                                regionTheme: theme,
                                visualTheme: visualTheme
                            )
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
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

    private func firstPersonView(theme: RegionTheme) -> some View {
        GeometryReader { proxy in
            let raySamples = depthRaySamples(columns: 96, maxDistance: 9.0)
            ZStack {
                Canvas { context, canvasSize in
                    drawDepthScene(into: &context, size: canvasSize, samples: raySamples, theme: theme)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("VIEW \(state.player.facing.shortLabel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)
                    Text("FIRST-PERSON")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.86))
                    Text("RAYCAST MAP  A/D TURN")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                    Text("W/S STEP  RANGE 9 TILES")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

                CrosshairView(color: palette.text.opacity(0.65))
                    .frame(width: 26, height: 26)
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

    private func depthRaySamples(columns: Int, maxDistance: Double) -> [DepthRaySample] {
        let origin = CGPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let caster = DepthRaycaster(origin: origin, facing: state.player.facing, fov: depthFieldOfView) { position in
            tile(at: position)
        }
        return caster.castSamples(columns: columns, maxDistance: maxDistance)
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

        if usesSkyBackdrop {
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

        let floorBands = 14
        for band in 0..<floorBands {
            let t0 = CGFloat(band) / CGFloat(floorBands)
            let t1 = CGFloat(band + 1) / CGFloat(floorBands)
            let y0 = horizon + (size.height - horizon) * pow(t0, 1.6)
            let y1 = horizon + (size.height - horizon) * pow(t1, 1.6)
            let rect = CGRect(x: 0, y: y0, width: size.width, height: max(1, y1 - y0))
            let shade = 0.10 + (Double(t1) * 0.22)
            let stripe = band.isMultiple(of: 2) ? theme.roomHighlight.opacity(0.05) : Color.black.opacity(0.04)
            context.fill(Path(rect), with: .color(theme.floor.opacity(shade)))
            context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe))

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
            let wallColor = frontWallColor(for: sample.hitTile, theme: theme).opacity(distanceShade * axisShade)
            context.fill(Path(rect), with: .color(wallColor))

            if sample.column.isMultiple(of: 3) {
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
        let billboards = depthBillboards(maxDistance: samples.first?.maxDistance ?? 9.0)
            .sorted { $0.distance > $1.distance }
        let horizon = size.height * 0.5
        let columnWidth = size.width / CGFloat(samples.count)

        for billboard in billboards {
            let screenCenter = ((billboard.angleOffset / depthFieldOfView) + 0.5) * size.width
            let projectedHeight = min(
                size.height * 0.88,
                CGFloat((size.height * billboard.scale) / max(0.16, billboard.distance))
            )
            let aspect = CGFloat(max(1, billboard.pattern.first?.count ?? 1)) / CGFloat(max(1, billboard.pattern.count))
            let projectedWidth = max(10, projectedHeight * aspect * billboard.widthScale)
            let left = screenCenter - (projectedWidth / 2)
            let top = horizon - (projectedHeight * 0.5)
            let cellWidth = projectedWidth / CGFloat(max(1, billboard.pattern.first?.count ?? 1))
            let cellHeight = projectedHeight / CGFloat(max(1, billboard.pattern.count))
            let shade = max(0.28, 1.0 - ((billboard.distance / billboard.maxDistance) * 0.72))
            let color = billboard.color.opacity(shade)

            for patternColumn in 0..<max(1, billboard.pattern.first?.count ?? 1) {
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

                for patternRow in 0..<billboard.pattern.count where billboard.pattern[patternRow][patternColumn] == 1 {
                    let rect = CGRect(
                        x: stripeMinX,
                        y: top + (CGFloat(patternRow) * cellHeight),
                        width: max(1, cellWidth),
                        height: max(1, cellHeight)
                    )
                    context.fill(Path(rect), with: .color(color))

                    if patternColumn == 0 || patternColumn == (billboard.pattern.first?.count ?? 1) - 1 {
                        let edge = CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
                        context.fill(Path(edge), with: .color(Color.black.opacity(0.18)))
                    }
                }
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
        switch feature {
        case .none:
            return nil
        case .chest:
            return (
                [
                    [1,1,1],
                    [1,0,1]
                ],
                palette.lightGold,
                0.44,
                0.84
            )
        case .bed:
            return (
                [
                    [1,1,1],
                    [1,0,0]
                ],
                palette.text,
                0.34,
                1.10
            )
        case .plateUp:
            return (
                [
                    [1,1],
                    [1,1]
                ],
                palette.accentViolet,
                0.22,
                1.30
            )
        case .plateDown:
            return (
                [
                    [1,1]
                ],
                palette.text.opacity(0.65),
                0.16,
                1.45
            )
        case .switchIdle:
            return (
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
            return (
                [
                    [1,1,1],
                    [1,1,1],
                    [1,1,1]
                ],
                palette.lightGold,
                0.28,
                0.84
            )
        case .shrine:
            return (
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
            return (
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
            return (
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

    private func firstPersonFeature(for feature: MapFeature, theme: RegionTheme, in frame: PerspectiveFrame) -> AnyView? {
        let color: Color
        let pattern: [[Int]]

        switch feature {
        case .none:
            return nil
        case .chest:
            color = palette.lightGold
            pattern = [
                [1,1,1],
                [1,0,1]
            ]
        case .bed:
            color = palette.text
            pattern = [
                [1,1,1],
                [1,0,0]
            ]
        case .plateUp:
            color = palette.accentViolet
            pattern = [
                [1,1],
                [1,1]
            ]
        case .plateDown:
            color = palette.text.opacity(0.65)
            pattern = [
                [1,1]
            ]
        case .switchIdle:
            color = palette.accentBlue
            pattern = [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        case .switchLit:
            color = palette.lightGold
            pattern = [
                [1,1,1],
                [1,1,1],
                [1,1,1]
            ]
        case .shrine:
            color = theme.shrine
            pattern = [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        case .beacon:
            color = theme.beacon
            pattern = [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        case .gate:
            color = theme.doorLocked
            pattern = [
                [1,0,1],
                [1,0,1],
                [1,1,1]
            ]
        }

        let spriteHeight = max(12, frame.height * 0.34)
        let spriteWidth = max(12, frame.width * 0.18)
        let view = PixelSprite(color: color, pattern: pattern)
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
            color = palette.text
            pattern = [
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
        case .boss:
            color = palette.accentViolet
            pattern = [
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
        switch state.player.currentMapID {
        case "merrow_village":
            return RegionTheme(
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
            return RegionTheme(
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
            return RegionTheme(
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
            return RegionTheme(
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
            return RegionTheme(
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
            return RegionTheme(
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
            return RegionTheme(
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
    }
}
