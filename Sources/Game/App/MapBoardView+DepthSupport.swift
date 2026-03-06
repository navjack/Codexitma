#if canImport(AppKit)
import Foundation
import SwiftUI

extension MapBoardView {
    func depthBillboards(maxDistance: Double) -> [DepthBillboard] {
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

                if let billboard = depthBillboard(
                    at: position,
                    distance: distance,
                    angleOffset: angleOffset,
                    maxDistance: maxDistance
                ) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
    }

    func depthBillboard(
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
        if feature != .none, let appearance = depthFeatureAppearance(for: feature) {
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

        let tile = tile(at: position)
        guard let appearance = depthTileBillboardAppearance(for: tile.type) else {
            return nil
        }
        let tileAppearance = depthTileAppearance(for: tile.type)
        return DepthBillboard(
            id: "tile:\(position.x):\(position.y):\(tile.type.rawValue)",
            pattern: tileAppearance.pattern,
            color: tileAppearance.color,
            distance: distance,
            angleOffset: angleOffset,
            maxDistance: maxDistance,
            scale: appearance.scale,
            widthScale: CGFloat(appearance.widthScale)
        )
    }

    var depthFieldOfView: Double {
        .pi / 3.1
    }

    var facingUnitVector: (x: Double, y: Double) {
        DepthProjectionMath.facingUnitVector(for: state.player.facing)
    }

    var rightUnitVector: (x: Double, y: Double) {
        DepthProjectionMath.rightUnitVector(for: state.player.facing)
    }

    var usesSkyBackdrop: Bool {
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
            "sanctum",
        ]
        return indoorFragments.allSatisfy { !mapID.contains($0) }
    }

    func corridorLayer(for slice: CorridorSlice, in size: CGSize, theme: RegionTheme) -> some View {
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

    func firstPersonFeature(
        for feature: MapFeature,
        theme _: RegionTheme,
        in frame: PerspectiveFrame
    ) -> AnyView? {
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

    func firstPersonOccupant(for occupant: MapOccupant, in frame: PerspectiveFrame) -> AnyView? {
        let color: Color
        let pattern: [[Int]]

        switch occupant {
        case .none:
            return nil
        case .player:
            color = GraphicsAssetCatalog.occupantSprite(for: "player")?.color.map(Self.swiftUIColor(from:)) ?? palette.text
            pattern = GraphicsAssetCatalog.occupantSprite(for: "player")?.pattern?.rows ?? [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1],
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
                    [1, 0, 1],
                    [1, 1, 1],
                    [1, 1, 1],
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

    func corridorGuide(from start: CGPoint, to end: CGPoint, intensity: Double) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(palette.text.opacity(intensity), lineWidth: 1)
    }

    func perspectiveFrame(depth: Int, in size: CGSize) -> PerspectiveFrame {
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

    func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.addLine(to: d)
            path.closeSubpath()
        }
    }

    func corridorSlices(maxDepth: Int = 4) -> [CorridorSlice] {
        var slices: [CorridorSlice] = []
        guard state.world.maps[state.player.currentMapID] != nil else { return slices }

        for depth in 0..<maxDepth {
            let frontPosition = advancedPosition(
                from: state.player.position,
                direction: state.player.facing,
                steps: depth + 1
            )
            let frontTile = tile(at: frontPosition)
            let leftTile = tile(
                at: advancedPosition(
                    from: frontPosition,
                    direction: state.player.facing.leftTurn,
                    steps: 1
                )
            )
            let rightTile = tile(
                at: advancedPosition(
                    from: frontPosition,
                    direction: state.player.facing.rightTurn,
                    steps: 1
                )
            )
            let slice = CorridorSlice(
                depth: depth,
                frontTile: frontTile,
                leftTile: leftTile,
                rightTile: rightTile,
                leftBlocked: leftTile.type.blocksDepthRay,
                rightBlocked: rightTile.type.blocksDepthRay,
                frontBlocked: frontTile.type.blocksDepthRay,
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

    func facingUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        DepthProjectionMath.facingUnitVector(for: direction)
    }

    func rightUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        DepthProjectionMath.rightUnitVector(for: direction)
    }

    func depthFloorProjection(
        size: CGSize,
        horizon: CGFloat,
        floorBands: Int,
        fieldOfView: Double,
        facing: Direction
    ) -> [DepthFloorBandProjection] {
        let key = DepthFloorProjectionKey(
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            horizonOffset: Int(horizon.rounded()),
            floorBands: floorBands,
            facing: facingKey(for: facing),
            fieldOfViewMilli: Int((fieldOfView * 1000.0).rounded())
        )
        if let cached = Self.depthFloorProjectionCache[key] {
            return cached
        }
        let projections = DepthProjectionMath.floorProjection(
            width: max(1, Int(size.width.rounded())),
            height: max(1, Int(size.height.rounded())),
            horizonOffset: Int(horizon.rounded()),
            floorBands: floorBands,
            facing: facing,
            fieldOfView: fieldOfView
        )

        Self.depthFloorProjectionCache[key] = projections
        if Self.depthFloorProjectionCache.count > 24 {
            Self.depthFloorProjectionCache.removeAll(keepingCapacity: true)
            Self.depthFloorProjectionCache[key] = projections
        }
        return projections
    }

    func facingKey(for direction: Direction) -> Int {
        DepthProjectionMath.facingKey(for: direction)
    }

    func lightValueString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func fract(_ value: Double) -> CGFloat {
        CGFloat(value - floor(value))
    }

    func advancedPosition(from start: Position, direction: Direction, steps: Int) -> Position {
        Position(
            x: start.x + (direction.delta.x * steps),
            y: start.y + (direction.delta.y * steps)
        )
    }

    func tile(at position: Position) -> Tile {
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

    func resolved(_ raw: Character) -> Character {
        if raw == "+", state.quests.has(.barrowUnlocked) {
            return "/"
        }
        return raw
    }

    func depthTileBillboardAppearance(for tileType: TileType) -> (scale: Double, widthScale: Double)? {
        switch tileType {
        case .stairs:
            return (0.32, 1.18)
        case .doorOpen:
            return (0.58, 0.90)
        case .brush:
            return (0.30, 1.12)
        case .shrine:
            return (0.46, 0.90)
        case .beacon:
            return (0.54, 0.92)
        case .floor, .wall, .water, .doorLocked:
            return nil
        }
    }

    func occupant(at position: Position) -> MapOccupant {
        if state.player.position == position {
            return .player
        }
        if let npc = state.world.npcs.first(where: {
            $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return .npc(npc.id)
        }
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return enemy.ai == .boss ? .boss(enemy.id) : .enemy(enemy.id)
        }
        return .none
    }

    func feature(at position: Position) -> MapFeature {
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

    var regionTheme: RegionTheme {
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

    func applyMapThemeOverride(base: RegionTheme, mapID: String) -> RegionTheme {
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

    static func swiftUIColor(from color: GraphicsRGBColor) -> Color {
        Color(
            red: Double(color.r) / 255.0,
            green: Double(color.g) / 255.0,
            blue: Double(color.b) / 255.0
        )
    }

    static func chamberPattern(from pattern: GraphicsFloorPatternName) -> ChamberPattern {
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
