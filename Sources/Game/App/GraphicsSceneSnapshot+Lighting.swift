import Foundation

private struct DepthLightBlockingGrid {
    let width: Int
    let height: Int
    let values: [Bool]

    func isBlocking(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else {
            return true
        }
        return values[(y * width) + x]
    }
}

extension GraphicsSceneSnapshotBuilder {
    static func makeDepthLightField(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double,
        subdivisions: Int,
        skyEmissive: Double
    ) -> DepthLightField {
        guard board.width > 0, board.height > 0 else {
            let baseAmbient = min(1.0, ambient + max(0.0, skyEmissive))
            return DepthLightField(
                width: board.width,
                height: board.height,
                ambient: baseAmbient,
                subdivisions: max(1, subdivisions),
                sampleWidth: 0,
                sampleHeight: 0,
                values: [],
                shadowValues: []
            )
        }
        let blockingGrid = makeLightBlockingGrid(board: board)

        let staticKey = staticLightCacheKey(
            from: state,
            board: board,
            ambient: ambient,
            subdivisions: subdivisions,
            skyEmissive: skyEmissive
        )
        let staticField: DepthLightField
        if let cached = cachedStaticLightField, cached.key == staticKey {
            staticField = cached.field
        } else {
            let staticSources = collectDepthLightSources(from: state, board: board)
            staticField = buildLightField(
                width: board.width,
                height: board.height,
                ambient: ambient,
                subdivisions: max(1, subdivisions),
                skyEmissive: skyEmissive,
                sources: staticSources,
                blockingGrid: blockingGrid
            )
            cachedStaticLightField = (staticKey, staticField)
        }

        guard isLanternDepthLightEnabled(for: state) else {
            return staticField
        }

        let lantern = playerLanternLightSource(for: state.player)
        let finalKey = DepthFinalLightCacheKey(
            staticKey: staticKey,
            playerPosition: state.player.position,
            lanternBucket: Int((lantern.intensity * 1000.0) + (lantern.radius * 100.0))
        )
        if let cached = cachedFinalLightField, cached.key == finalKey {
            return cached.field
        }

        var values = staticField.values
        var shadowValues = staticField.shadowValues
        applyLightSource(
            lantern,
            lightValues: &values,
            shadowValues: &shadowValues,
            field: staticField,
            blockingGrid: blockingGrid
        )
        shadowValues = softenedShadowMask(shadowValues)
        let finalField = DepthLightField(
            width: board.width,
            height: board.height,
            ambient: staticField.ambient,
            subdivisions: staticField.subdivisions,
            sampleWidth: staticField.sampleWidth,
            sampleHeight: staticField.sampleHeight,
            values: values,
            shadowValues: shadowValues
        )
        cachedFinalLightField = (finalKey, finalField)
        return finalField
    }

    static func isLanternDepthLightEnabled(for state: GameState) -> Bool {
        // Lantern light in Depth3D is opt-in; default runs should rely on world lights.
        state.world.openedInteractables.contains("lantern_enabled")
    }

    static func staticLightCacheKey(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double,
        subdivisions: Int,
        skyEmissive: Double
    ) -> DepthStaticLightCacheKey {
        let openedInteractablesHash = hashStrings(state.world.openedInteractables)
        let bossMarkers = state.world.enemies
            .filter { $0.active && $0.ai == .boss && $0.mapID == state.player.currentMapID }
            .map { "\($0.id):\($0.position.x):\($0.position.y):\($0.hp)" }
        let bossStateHash = hashStrings(bossMarkers)
        return DepthStaticLightCacheKey(
            mapID: state.player.currentMapID,
            width: board.width,
            height: board.height,
            subdivisions: max(1, subdivisions),
            ambientBucket: Int(ambient * 1000.0),
            skyEmissiveBucket: Int(skyEmissive * 1000.0),
            openedInteractablesHash: openedInteractablesHash,
            bossStateHash: bossStateHash
        )
    }

    static func hashStrings<S: Sequence>(_ values: S) -> Int where S.Element == String {
        var hasher = Hasher()
        let sorted = Array(values).sorted()
        for value in sorted {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    static func playerLanternLightSource(for player: PlayerState) -> DepthLightSource {
        let lanternStrength = max(0.0, min(1.0, Double(player.effectiveLanternCapacity()) / 18.0))
        return DepthLightSource(
            position: player.position,
            intensity: 0.22 + (lanternStrength * 0.22),
            radius: 2.8 + (lanternStrength * 2.4),
            blockedTransmission: 0.10 + (lanternStrength * 0.06),
            shadowStrength: 0.14 + (lanternStrength * 0.12)
        )
    }

    fileprivate static func buildLightField(
        width: Int,
        height: Int,
        ambient: Double,
        subdivisions: Int,
        skyEmissive: Double,
        sources: [DepthLightSource],
        blockingGrid: DepthLightBlockingGrid
    ) -> DepthLightField {
        let sampleScale = max(1, subdivisions)
        let sampleWidth = max(0, width * sampleScale)
        let sampleHeight = max(0, height * sampleScale)
        let baseAmbient = min(1.0, ambient + max(0.0, skyEmissive))
        var values = Array(
            repeating: Array(repeating: baseAmbient, count: sampleWidth),
            count: sampleHeight
        )
        var shadowValues = Array(
            repeating: Array(repeating: 0.0, count: sampleWidth),
            count: sampleHeight
        )
        let field = DepthLightField(
            width: width,
            height: height,
            ambient: baseAmbient,
            subdivisions: sampleScale,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            values: values,
            shadowValues: shadowValues
        )
        for source in sources {
            applyLightSource(
                source,
                lightValues: &values,
                shadowValues: &shadowValues,
                field: field,
                blockingGrid: blockingGrid
            )
        }
        shadowValues = softenedShadowMask(shadowValues)
        return DepthLightField(
            width: width,
            height: height,
            ambient: baseAmbient,
            subdivisions: sampleScale,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            values: values,
            shadowValues: shadowValues
        )
    }

    fileprivate static func applyLightSource(
        _ source: DepthLightSource,
        lightValues: inout [[Double]],
        shadowValues: inout [[Double]],
        field: DepthLightField,
        blockingGrid: DepthLightBlockingGrid
    ) {
        guard blockingGrid.width > 0,
              blockingGrid.height > 0,
              field.sampleWidth > 0,
              field.sampleHeight > 0 else {
            return
        }

        let sourceWorldX = Double(source.position.x) + 0.5
        let sourceWorldY = Double(source.position.y) + 0.5
        let sampleScale = Double(field.subdivisions)

        let minSampleX = max(0, Int(floor((sourceWorldX - source.radius) * sampleScale)))
        let maxSampleX = min(
            field.sampleWidth - 1,
            Int(ceil((sourceWorldX + source.radius) * sampleScale))
        )
        let minSampleY = max(0, Int(floor((sourceWorldY - source.radius) * sampleScale)))
        let maxSampleY = min(
            field.sampleHeight - 1,
            Int(ceil((sourceWorldY + source.radius) * sampleScale))
        )

        guard minSampleX <= maxSampleX, minSampleY <= maxSampleY else {
            return
        }

        for sampleY in minSampleY...maxSampleY {
            let worldY = (Double(sampleY) + 0.5) / sampleScale
            for sampleX in minSampleX...maxSampleX {
                let worldX = (Double(sampleX) + 0.5) / sampleScale
                let dx = sourceWorldX - worldX
                let dy = sourceWorldY - worldY
                let distance = hypot(dx, dy)
                if distance > source.radius {
                    continue
                }

                let attenuation = pow(max(0.0, 1.0 - (distance / source.radius)), 1.25)
                var contribution = source.intensity * attenuation
                let blocked = !hasLightLineOfSight(
                    fromWorldX: sourceWorldX,
                    y: sourceWorldY,
                    toWorldX: worldX,
                    y: worldY,
                    blockingGrid: blockingGrid
                )
                if blocked {
                    contribution *= source.blockedTransmission
                }
                var next = lightValues[sampleY][sampleX]
                next += contribution
                let minimum = max(0.01, field.ambient * 0.12)
                lightValues[sampleY][sampleX] = max(minimum, min(1.0, next))

                if blocked {
                    let occlusion = max(0.0, 1.0 - source.blockedTransmission)
                    let shadowContribution = source.shadowStrength * attenuation * occlusion
                    let shadowNext = shadowValues[sampleY][sampleX] + shadowContribution
                    shadowValues[sampleY][sampleX] = max(0.0, min(1.0, shadowNext))
                }
            }
        }
    }

    static func softenedShadowMask(_ values: [[Double]]) -> [[Double]] {
        guard !values.isEmpty, !values[0].isEmpty else {
            return values
        }

        let height = values.count
        let width = values[0].count
        var output = values

        for y in 0..<height {
            for x in 0..<width {
                var weightedSum = 0.0
                var totalWeight = 0.0

                for dy in -1...1 {
                    for dx in -1...1 {
                        let sampleX = min(max(0, x + dx), width - 1)
                        let sampleY = min(max(0, y + dy), height - 1)
                        let weightX = dx == 0 ? 2.0 : 1.0
                        let weightY = dy == 0 ? 2.0 : 1.0
                        let weight = weightX * weightY
                        weightedSum += values[sampleY][sampleX] * weight
                        totalWeight += weight
                    }
                }

                output[y][x] = max(0.0, min(1.0, weightedSum / max(1.0, totalWeight)))
            }
        }

        return output
    }

    static func collectDepthLightSources(from state: GameState, board: MapBoardSnapshot) -> [DepthLightSource] {
        var sources: [DepthLightSource] = []

        for row in board.rows {
            for cell in row {
                if let source = depthLightSource(for: cell) {
                    sources.append(source)
                }
            }
        }

        if state.world.openedInteractables.contains("spire_mirrors_aligned"),
           let spireMap = state.world.maps["beacon_spire"] {
            for interactable in spireMap.interactables where interactable.kind == .switchRune {
                sources.append(
                    DepthLightSource(
                        position: interactable.position,
                        intensity: 0.22,
                        radius: 2.6,
                        blockedTransmission: 0.18,
                        shadowStrength: 0.06
                    )
                )
            }
        }

        return sources
    }

    static func depthLightSource(for cell: BoardCellSnapshot) -> DepthLightSource? {
        switch cell.feature {
        case .beacon:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.90,
                radius: 8.2,
                blockedTransmission: 0.34,
                shadowStrength: 0.03
            )
        case .shrine:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.58,
                radius: 5.2,
                blockedTransmission: 0.28,
                shadowStrength: 0.05
            )
        case .switchLit:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.38,
                radius: 3.8,
                blockedTransmission: 0.22,
                shadowStrength: 0.08
            )
        case .torchFloor:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.72,
                radius: 5.2,
                blockedTransmission: 0.0,
                shadowStrength: 0.52
            )
        case .torchWall:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.64,
                radius: 4.7,
                blockedTransmission: 0.0,
                shadowStrength: 0.58
            )
        case .gate:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.16,
                radius: 2.1,
                blockedTransmission: 0.20,
                shadowStrength: 0.04
            )
        case .none, .chest, .bed, .plateUp, .plateDown, .switchIdle:
            break
        }

        switch cell.tile.type {
        case .doorOpen:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.30,
                radius: 3.2,
                blockedTransmission: 0.12,
                shadowStrength: 0.12
            )
        case .beacon:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.74,
                radius: 6.8,
                blockedTransmission: 0.32,
                shadowStrength: 0.03
            )
        default:
            break
        }

        switch cell.occupant {
        case .boss:
            return DepthLightSource(
                position: cell.position,
                intensity: 0.28,
                radius: 3.3,
                blockedTransmission: 0.20,
                shadowStrength: 0.09
            )
        case .none, .player, .npc, .enemy:
            return nil
        }
    }

    fileprivate static func hasLightLineOfSight(
        fromWorldX startX: Double,
        y startY: Double,
        toWorldX endX: Double,
        y endY: Double,
        blockingGrid: DepthLightBlockingGrid
    ) -> Bool {
        let dx = endX - startX
        let dy = endY - startY
        let distance = hypot(dx, dy)
        if distance < 0.05 {
            return true
        }

        let startTileX = Int(floor(startX))
        let startTileY = Int(floor(startY))
        let endTileX = Int(floor(endX))
        let endTileY = Int(floor(endY))

        var tileX = startTileX
        var tileY = startTileY

        let stepX = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
        let stepY = dy > 0 ? 1 : (dy < 0 ? -1 : 0)

        let tDeltaX = stepX == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / dx)
        let tDeltaY = stepY == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / dy)

        let tMaxX: Double = {
            if stepX > 0 {
                return (Double(tileX + 1) - startX) / dx
            }
            if stepX < 0 {
                return (startX - Double(tileX)) / -dx
            }
            return Double.greatestFiniteMagnitude
        }()

        let tMaxY: Double = {
            if stepY > 0 {
                return (Double(tileY + 1) - startY) / dy
            }
            if stepY < 0 {
                return (startY - Double(tileY)) / -dy
            }
            return Double.greatestFiniteMagnitude
        }()

        var rayTMaxX = tMaxX
        var rayTMaxY = tMaxY

        while tileX != endTileX || tileY != endTileY {
            if rayTMaxX < rayTMaxY {
                tileX += stepX
                rayTMaxX += tDeltaX
                if isBlockingLightTile(
                    x: tileX,
                    y: tileY,
                    startX: startTileX,
                    startY: startTileY,
                    endX: endTileX,
                    endY: endTileY,
                    blockingGrid: blockingGrid
                ) {
                    return false
                }
            } else if rayTMaxY < rayTMaxX {
                tileY += stepY
                rayTMaxY += tDeltaY
                if isBlockingLightTile(
                    x: tileX,
                    y: tileY,
                    startX: startTileX,
                    startY: startTileY,
                    endX: endTileX,
                    endY: endTileY,
                    blockingGrid: blockingGrid
                ) {
                    return false
                }
            } else {
                // Supercover corner crossing: test both orthogonal neighbors plus the diagonal.
                let nextX = tileX + stepX
                let nextY = tileY + stepY

                if isBlockingLightTile(
                    x: nextX,
                    y: tileY,
                    startX: startTileX,
                    startY: startTileY,
                    endX: endTileX,
                    endY: endTileY,
                    blockingGrid: blockingGrid
                ) {
                    return false
                }
                if isBlockingLightTile(
                    x: tileX,
                    y: nextY,
                    startX: startTileX,
                    startY: startTileY,
                    endX: endTileX,
                    endY: endTileY,
                    blockingGrid: blockingGrid
                ) {
                    return false
                }

                tileX = nextX
                tileY = nextY
                rayTMaxX += tDeltaX
                rayTMaxY += tDeltaY

                if isBlockingLightTile(
                    x: tileX,
                    y: tileY,
                    startX: startTileX,
                    startY: startTileY,
                    endX: endTileX,
                    endY: endTileY,
                    blockingGrid: blockingGrid
                ) {
                    return false
                }
            }
        }

        return true
    }

    fileprivate static func isBlockingLightTile(
        x: Int,
        y: Int,
        startX: Int,
        startY: Int,
        endX: Int,
        endY: Int,
        blockingGrid: DepthLightBlockingGrid
    ) -> Bool {
        if (x == startX && y == startY) || (x == endX && y == endY) {
            return false
        }
        return blockingGrid.isBlocking(x: x, y: y)
    }

    fileprivate static func makeLightBlockingGrid(board: MapBoardSnapshot) -> DepthLightBlockingGrid {
        let values = board.rows.flatMap { row in
            row.map { $0.tile.type.blocksDepthLighting }
        }
        return DepthLightBlockingGrid(width: board.width, height: board.height, values: values)
    }

    static func resolved(_ raw: Character, state: GameState) -> Character {
        if raw == "+", state.quests.has(.barrowUnlocked) {
            return "/"
        }
        return raw
    }

    static func depthBackdropStyle(for state: GameState, mapID: String) -> DepthBackdropStyle {
        if let configured = state.world.maps[mapID]?.depthBackdrop {
            return configured
        }
        return inferredDepthBackdrop(for: mapID)
    }

    static func inferredDepthBackdrop(for mapID: String) -> DepthBackdropStyle {
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
        return indoorFragments.allSatisfy { !mapID.contains($0) } ? .sky : .ceiling
    }

    static func facingAngle(for direction: Direction) -> Double {
        switch direction {
        case .up:
            return -.pi / 2
        case .down:
            return .pi / 2
        case .left:
            return .pi
        case .right:
            return 0
        }
    }

    static func facingUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        DepthProjectionMath.facingUnitVector(for: direction)
    }

    static func rightUnitVector(for direction: Direction) -> (x: Double, y: Double) {
        DepthProjectionMath.rightUnitVector(for: direction)
    }
}
