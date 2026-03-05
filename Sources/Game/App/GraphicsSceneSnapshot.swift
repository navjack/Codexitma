import Foundation

enum MapOccupant {
    case none
    case player
    case npc(String)
    case enemy(String)
    case boss(String)
}

enum MapFeature {
    case none
    case chest
    case bed
    case plateUp
    case plateDown
    case switchIdle
    case switchLit
    case torchFloor
    case torchWall
    case shrine
    case beacon
    case gate

    var debugName: String {
        switch self {
        case .none: return "none"
        case .chest: return "chest"
        case .bed: return "bed"
        case .plateUp: return "plate_up"
        case .plateDown: return "plate_down"
        case .switchIdle: return "switch_idle"
        case .switchLit: return "switch_lit"
        case .torchFloor: return "torch_floor"
        case .torchWall: return "torch_wall"
        case .shrine: return "shrine"
        case .beacon: return "beacon"
        case .gate: return "gate"
        }
    }
}

enum DepthBillboardKind {
    case npc(String)
    case enemy(String)
    case boss(String)
    case feature(MapFeature)
    case tile(TileType)
}

struct BoardCellSnapshot {
    let position: Position
    let tile: Tile
    let occupant: MapOccupant
    let feature: MapFeature
}

struct MapBoardSnapshot {
    let width: Int
    let height: Int
    let rows: [[BoardCellSnapshot]]

    func cell(at position: Position) -> BoardCellSnapshot? {
        guard position.y >= 0,
              position.y < rows.count,
              position.x >= 0,
              position.x < rows[position.y].count else {
            return nil
        }
        return rows[position.y][position.x]
    }
}

struct DepthBillboardSnapshot {
    let id: String
    let kind: DepthBillboardKind
    let distance: Double
    let angleOffset: Double
    let maxDistance: Double
    let scale: Double
    let widthScale: Double
    let lightLevel: Double
}

struct DepthFloorLightingSnapshot {
    let columns: Int
    let bands: Int
    let ambient: Double
    let values: [[Double]]

    func level(column: Int, band: Int) -> Double {
        guard band >= 0,
              band < values.count,
              column >= 0,
              !values.isEmpty,
              column < values[band].count else {
            return ambient
        }
        return values[band][column]
    }

    func interpolatedLevel(xNormalized: Double, yNormalized: Double) -> Double {
        guard !values.isEmpty, columns > 0, bands > 0 else {
            return ambient
        }

        let x = max(0.0, min(1.0, xNormalized)) * Double(max(0, columns - 1))
        let y = max(0.0, min(1.0, yNormalized)) * Double(max(0, bands - 1))
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(columns - 1, x0 + 1)
        let y1 = min(bands - 1, y0 + 1)
        let tx = x - Double(x0)
        let ty = y - Double(y0)

        let top = (level(column: x0, band: y0) * (1.0 - tx)) + (level(column: x1, band: y0) * tx)
        let bottom = (level(column: x0, band: y1) * (1.0 - tx)) + (level(column: x1, band: y1) * tx)
        return max(0.0, min(1.0, (top * (1.0 - ty)) + (bottom * ty)))
    }
}

struct DepthTileLightingSnapshot {
    let width: Int
    let height: Int
    let ambient: Double
    let values: [[Double]]

    func level(at position: Position) -> Double {
        guard position.x >= 0,
              position.y >= 0,
              position.y < values.count,
              position.x < values[position.y].count else {
            return ambient
        }
        return values[position.y][position.x]
    }
}

struct DepthWorldLightingSnapshot {
    let width: Int
    let height: Int
    let ambient: Double
    let subdivisions: Int
    let sampleWidth: Int
    let sampleHeight: Int
    let values: [[Double]]
    let shadowValues: [[Double]]

    func level(atWorldX worldX: Double, y worldY: Double) -> Double {
        sample(from: values, atWorldX: worldX, y: worldY)
    }

    func shadowLevel(atWorldX worldX: Double, y worldY: Double) -> Double {
        sample(from: shadowValues, atWorldX: worldX, y: worldY)
    }

    func effectiveLevel(
        atWorldX worldX: Double,
        y worldY: Double,
        shadowWeight: Double = 0.74,
        minimumAmbientFactor: Double = 0.10
    ) -> Double {
        let light = level(atWorldX: worldX, y: worldY)
        let shadow = shadowLevel(atWorldX: worldX, y: worldY)
        let shaded = light - (shadow * shadowWeight)
        let minimum = max(0.01, ambient * minimumAmbientFactor)
        return max(minimum, min(1.0, shaded))
    }

    private func sample(from grid: [[Double]], atWorldX worldX: Double, y worldY: Double) -> Double {
        guard worldX >= 0.0,
              worldY >= 0.0,
              worldX < Double(width),
              worldY < Double(height) else {
            return ambient
        }

        guard sampleWidth > 0, sampleHeight > 0, !grid.isEmpty else {
            return ambient
        }

        let scaledX = (worldX * Double(subdivisions)) - 0.5
        let scaledY = (worldY * Double(subdivisions)) - 0.5
        let clampedX = max(0.0, min(Double(sampleWidth - 1), scaledX))
        let clampedY = max(0.0, min(Double(sampleHeight - 1), scaledY))

        let x0 = Int(floor(clampedX))
        let y0 = Int(floor(clampedY))
        let x1 = min(sampleWidth - 1, x0 + 1)
        let y1 = min(sampleHeight - 1, y0 + 1)
        let tx = clampedX - Double(x0)
        let ty = clampedY - Double(y0)

        let top = (grid[y0][x0] * (1.0 - tx)) + (grid[y0][x1] * tx)
        let bottom = (grid[y1][x0] * (1.0 - tx)) + (grid[y1][x1] * tx)
        return max(0.0, min(1.0, (top * (1.0 - ty)) + (bottom * ty)))
    }
}

struct DepthSceneSnapshot {
    let facing: Direction
    let fieldOfView: Double
    let maxDistance: Double
    let usesSkyBackdrop: Bool
    let samples: [DepthRaySample]
    let billboards: [DepthBillboardSnapshot]
    let floorLighting: DepthFloorLightingSnapshot
    let tileLighting: DepthTileLightingSnapshot
    let worldLighting: DepthWorldLightingSnapshot
}

struct InventoryEntrySnapshot {
    let index: Int
    let name: String
    let isSelected: Bool
    let isEquipped: Bool
}

struct ShopOfferSnapshot {
    let index: Int
    let label: String
    let price: Int
    let blurb: String
    let isSelected: Bool
    let soldOut: Bool
}

struct GraphicsSceneSnapshot {
    let mode: GameMode
    let visualTheme: GraphicsVisualTheme
    let adventureTitle: String
    let adventureSummary: String
    let currentMapID: String
    let board: MapBoardSnapshot
    let depth: DepthSceneSnapshot?
    let mapLighting: DepthTileLightingSnapshot?
    let messages: [String]
    let player: PlayerState
    let quests: QuestState
    let questFlow: QuestFlowDefinition
    let availableAdventures: [AdventureCatalogEntry]
    let selectedAdventureIndex: Int
    let heroOptions: [HeroClass]
    let selectedHeroIndex: Int
    let selectedHeroClass: HeroClass
    let selectedHeroSummary: String
    let selectedHeroTraitsPrimary: String
    let selectedHeroTraitsSecondary: String
    let selectedHeroSkills: [String]
    let currentObjective: String
    let currentDialogueSpeaker: String?
    let currentDialogueLines: [String]
    let inventoryEntries: [InventoryEntrySnapshot]
    let inventorySelectionIndex: Int
    let inventoryDetail: String?
    let shopTitle: String?
    let shopLines: [String]
    let shopOffers: [ShopOfferSnapshot]
    let shopSelectionIndex: Int
    let shopDetail: String?
}

enum GraphicsSceneSnapshotBuilder {
    private static let defaultDepthFieldOfView = Double.pi / 3.1

    private struct DepthRenderProfile {
        let fieldOfView: Double
        let maxDistance: Double
        let columns: Int
        let ambientLight: Double
        let lightSubdivisions: Int
        let floorLightBands: Int
    }

    private struct DepthLightSource {
        let position: Position
        let intensity: Double
        let radius: Double
        let blockedTransmission: Double
        let shadowStrength: Double
    }

    private struct DepthLightField {
        let width: Int
        let height: Int
        let ambient: Double
        let subdivisions: Int
        let sampleWidth: Int
        let sampleHeight: Int
        let values: [[Double]]
        let shadowValues: [[Double]]

        func level(at position: Position) -> Double {
            level(
                atWorldX: Double(position.x) + 0.5,
                y: Double(position.y) + 0.5
            )
        }

        func level(atWorldX worldX: Double, y worldY: Double) -> Double {
            sample(from: values, atWorldX: worldX, y: worldY)
        }

        func shadowLevel(at position: Position) -> Double {
            shadowLevel(
                atWorldX: Double(position.x) + 0.5,
                y: Double(position.y) + 0.5
            )
        }

        func shadowLevel(atWorldX worldX: Double, y worldY: Double) -> Double {
            sample(from: shadowValues, atWorldX: worldX, y: worldY)
        }

        func effectiveLevel(
            at position: Position,
            shadowWeight: Double = 0.74,
            minimumAmbientFactor: Double = 0.10
        ) -> Double {
            effectiveLevel(
                atWorldX: Double(position.x) + 0.5,
                y: Double(position.y) + 0.5,
                shadowWeight: shadowWeight,
                minimumAmbientFactor: minimumAmbientFactor
            )
        }

        func effectiveLevel(
            atWorldX worldX: Double,
            y worldY: Double,
            shadowWeight: Double = 0.74,
            minimumAmbientFactor: Double = 0.10
        ) -> Double {
            let light = level(atWorldX: worldX, y: worldY)
            let shadow = shadowLevel(atWorldX: worldX, y: worldY)
            let shaded = light - (shadow * shadowWeight)
            let minimum = max(0.01, ambient * minimumAmbientFactor)
            return max(minimum, min(1.0, shaded))
        }

        private func sample(from grid: [[Double]], atWorldX worldX: Double, y worldY: Double) -> Double {
            guard worldX >= 0.0,
                  worldY >= 0.0,
                  worldX < Double(width),
                  worldY < Double(height) else {
                return ambient
            }

            guard sampleWidth > 0, sampleHeight > 0, !grid.isEmpty else {
                return ambient
            }

            let scaledX = (worldX * Double(subdivisions)) - 0.5
            let scaledY = (worldY * Double(subdivisions)) - 0.5
            let clampedX = max(0.0, min(Double(sampleWidth - 1), scaledX))
            let clampedY = max(0.0, min(Double(sampleHeight - 1), scaledY))

            let x0 = Int(floor(clampedX))
            let y0 = Int(floor(clampedY))
            let x1 = min(sampleWidth - 1, x0 + 1)
            let y1 = min(sampleHeight - 1, y0 + 1)
            let tx = clampedX - Double(x0)
            let ty = clampedY - Double(y0)

            let top = (grid[y0][x0] * (1.0 - tx)) + (grid[y0][x1] * tx)
            let bottom = (grid[y1][x0] * (1.0 - tx)) + (grid[y1][x1] * tx)
            return max(0.0, min(1.0, (top * (1.0 - ty)) + (bottom * ty)))
        }
    }

    private struct DepthStaticLightCacheKey: Hashable {
        let mapID: String
        let width: Int
        let height: Int
        let subdivisions: Int
        let ambientBucket: Int
        let openedInteractablesHash: Int
        let bossStateHash: Int
    }

    private struct DepthFinalLightCacheKey: Hashable {
        let staticKey: DepthStaticLightCacheKey
        let playerPosition: Position
        let lanternBucket: Int
    }

    private nonisolated(unsafe) static var cachedStaticLightField: (key: DepthStaticLightCacheKey, field: DepthLightField)?
    private nonisolated(unsafe) static var cachedFinalLightField: (key: DepthFinalLightCacheKey, field: DepthLightField)?

    static func build(state: GameState, visualTheme: GraphicsVisualTheme) -> GraphicsSceneSnapshot {
        let board = makeBoard(from: state)
        let depth = visualTheme == .depth3D ? makeDepthScene(from: state, board: board) : nil
        let mapLighting = depth?.tileLighting ?? makeMapLighting(from: state, board: board)
        let selectedHeroClass = state.selectedHeroClass()
        let selectedHeroTemplate = heroTemplate(for: selectedHeroClass)

        return GraphicsSceneSnapshot(
            mode: state.mode,
            visualTheme: visualTheme,
            adventureTitle: state.selectedAdventureTitle(),
            adventureSummary: state.selectedAdventureSummary(),
            currentMapID: state.player.currentMapID,
            board: board,
            depth: depth,
            mapLighting: mapLighting,
            messages: state.messages,
            player: state.player,
            quests: state.quests,
            questFlow: state.questFlow,
            availableAdventures: state.availableAdventures,
            selectedAdventureIndex: state.selectedAdventureIndex,
            heroOptions: HeroClass.allCases,
            selectedHeroIndex: state.selectedHeroIndex,
            selectedHeroClass: selectedHeroClass,
            selectedHeroSummary: selectedHeroTemplate.summary,
            selectedHeroTraitsPrimary: traitSummaryLine(selectedHeroTemplate.traits),
            selectedHeroTraitsSecondary: traitSummaryLineSecondary(selectedHeroTemplate.traits),
            selectedHeroSkills: selectedHeroTemplate.skills.map(\.displayName),
            currentObjective: QuestSystem.objective(for: state.quests, flow: state.questFlow),
            currentDialogueSpeaker: state.currentDialogue?.speaker,
            currentDialogueLines: state.currentDialogue?.lines ?? [],
            inventoryEntries: inventoryEntries(from: state),
            inventorySelectionIndex: state.inventorySelectionIndex,
            inventoryDetail: inventoryDetail(from: state),
            shopTitle: state.shopTitle,
            shopLines: state.shopLines,
            shopOffers: shopOffers(from: state),
            shopSelectionIndex: state.shopSelectionIndex,
            shopDetail: state.shopDetail
        )
    }

    private static func traitSummaryLine(_ traits: TraitProfile) -> String {
        "\(TraitStat.brawn.shortLabel):\(traits.brawn) \(TraitStat.agility.shortLabel):\(traits.agility) \(TraitStat.grit.shortLabel):\(traits.grit)"
    }

    private static func traitSummaryLineSecondary(_ traits: TraitProfile) -> String {
        "\(TraitStat.wits.shortLabel):\(traits.wits) \(TraitStat.lore.shortLabel):\(traits.lore) \(TraitStat.spark.shortLabel):\(traits.spark)"
    }

    private static func inventoryEntries(from state: GameState) -> [InventoryEntrySnapshot] {
        state.player.inventory.enumerated().map { index, item in
            InventoryEntrySnapshot(
                index: index,
                name: item.name,
                isSelected: index == state.inventorySelectionIndex,
                isEquipped: EquipmentSlot.allCases.contains { state.player.equipment.itemID(for: $0) == item.id }
            )
        }
    }

    private static func inventoryDetail(from state: GameState) -> String? {
        guard !state.player.inventory.isEmpty else {
            return nil
        }
        let index = max(0, min(state.inventorySelectionIndex, state.player.inventory.count - 1))
        let item = state.player.inventory[index]

        if item.isEquippable, let slot = item.slot {
            return "\(item.name): \(slot.rawValue) +A\(item.attackBonus) +D\(item.defenseBonus) +L\(item.lanternBonus)"
        }

        switch item.kind {
        case .consumable:
            return "\(item.name): restores \(item.value)."
        case .upgrade:
            return "\(item.name): permanent boon when used."
        case .key, .quest:
            return "\(item.name): important, but not directly usable."
        case .equipment:
            return "\(item.name): equipable gear."
        }
    }

    private static func shopOffers(from state: GameState) -> [ShopOfferSnapshot] {
        state.shopOffers.enumerated().map { index, offer in
            let soldOut = !offer.repeatable && state.world.purchasedShopOffers.contains(offer.id)
            let itemName = itemTable[offer.itemID]?.name ?? offer.itemID.rawValue
            return ShopOfferSnapshot(
                index: index,
                label: itemName,
                price: offer.price,
                blurb: offer.blurb,
                isSelected: index == state.shopSelectionIndex,
                soldOut: soldOut
            )
        }
    }

    private static func makeBoard(from state: GameState) -> MapBoardSnapshot {
        guard let map = state.world.maps[state.player.currentMapID] else {
            return MapBoardSnapshot(width: 0, height: 0, rows: [])
        }

        let rows = map.lines.enumerated().map { y, line in
            Array(line).enumerated().map { x, raw in
                let position = Position(x: x, y: y)
                return BoardCellSnapshot(
                    position: position,
                    tile: TileFactory.tile(for: resolved(raw, state: state)),
                    occupant: occupant(at: position, state: state),
                    feature: feature(at: position, state: state)
                )
            }
        }

        return MapBoardSnapshot(
            width: rows.first?.count ?? 0,
            height: rows.count,
            rows: rows
        )
    }

    private static func makeDepthScene(from state: GameState, board: MapBoardSnapshot) -> DepthSceneSnapshot {
        let mapID = state.player.currentMapID
        let skyBackdrop = usesSkyBackdrop(for: mapID)
        let profile = depthRenderProfile(for: mapID, usesSkyBackdrop: skyBackdrop)
        let lightField = makeDepthLightField(
            from: state,
            board: board,
            ambient: profile.ambientLight,
            subdivisions: profile.lightSubdivisions
        )

        let origin = DepthPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let caster = DepthRaycaster(
            origin: origin,
            facing: state.player.facing,
            fov: profile.fieldOfView,
            lightAt: { position in
                lightField.level(at: position)
            },
            lightAtWorld: { worldX, worldY in
                lightField.level(atWorldX: worldX, y: worldY)
            },
            shadowAtWorld: { worldX, worldY in
                lightField.shadowLevel(atWorldX: worldX, y: worldY)
            }
        ) { position in
            board.cell(at: position)?.tile ?? TileFactory.tile(for: "#")
        }

        let samples = caster.castSamples(columns: profile.columns, maxDistance: profile.maxDistance)
        let billboards = makeDepthBillboards(
            from: state,
            board: board,
            fieldOfView: profile.fieldOfView,
            maxDistance: profile.maxDistance,
            lightField: lightField
        )
            .sorted { $0.distance > $1.distance }
        let floorLighting = makeDepthFloorLighting(
            from: state,
            lightField: lightField,
            fieldOfView: profile.fieldOfView,
            maxDistance: profile.maxDistance,
            columns: profile.columns,
            bands: profile.floorLightBands
        )
        let tileLighting = makeDepthTileLighting(board: board, lightField: lightField)
        let worldLighting = makeDepthWorldLighting(lightField: lightField)

        return DepthSceneSnapshot(
            facing: state.player.facing,
            fieldOfView: profile.fieldOfView,
            maxDistance: profile.maxDistance,
            usesSkyBackdrop: skyBackdrop,
            samples: samples,
            billboards: billboards,
            floorLighting: floorLighting,
            tileLighting: tileLighting,
            worldLighting: worldLighting
        )
    }

    private static func makeMapLighting(from state: GameState, board: MapBoardSnapshot) -> DepthTileLightingSnapshot? {
        guard board.width > 0, board.height > 0 else {
            return nil
        }
        let mapID = state.player.currentMapID
        let profile = depthRenderProfile(for: mapID, usesSkyBackdrop: usesSkyBackdrop(for: mapID))
        let lightField = makeDepthLightField(
            from: state,
            board: board,
            ambient: profile.ambientLight,
            subdivisions: profile.lightSubdivisions
        )
        return makeDepthTileLighting(board: board, lightField: lightField)
    }

    private static func makeDepthBillboards(
        from state: GameState,
        board: MapBoardSnapshot,
        fieldOfView: Double,
        maxDistance: Double,
        lightField: DepthLightField
    ) -> [DepthBillboardSnapshot] {
        let playerCenter = (
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let forward = facingUnitVector(for: state.player.facing)
        let right = rightUnitVector(for: state.player.facing)
        var billboards: [DepthBillboardSnapshot] = []

        for row in board.rows {
            for cell in row where cell.position != state.player.position {
                let worldX = Double(cell.position.x) + 0.5
                let worldY = Double(cell.position.y) + 0.5
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
                if abs(angleOffset) > (fieldOfView * 0.65) {
                    continue
                }

                if let billboard = makeBillboard(
                    for: cell,
                    distance: distance,
                    angleOffset: angleOffset,
                    maxDistance: maxDistance,
                    lightLevel: lightField.effectiveLevel(
                        at: cell.position,
                        shadowWeight: 0.76,
                        minimumAmbientFactor: 0.08
                    )
                ) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
    }

    private static func makeDepthFloorLighting(
        from state: GameState,
        lightField: DepthLightField,
        fieldOfView: Double,
        maxDistance: Double,
        columns: Int,
        bands: Int
    ) -> DepthFloorLightingSnapshot {
        let safeColumns = max(1, columns)
        let safeBands = max(8, bands)
        let originX = Double(state.player.position.x) + 0.5
        let originY = Double(state.player.position.y) + 0.5
        let baseAngle = facingAngle(for: state.player.facing)

        let values: [[Double]] = (0..<safeBands).map { band in
            let t = (Double(band) + 0.5) / Double(safeBands)
            let distance = 0.72 + (pow(1.0 - t, 1.45) * (maxDistance - 0.72))
            return (0..<safeColumns).map { column in
                let cameraOffset = ((Double(column) + 0.5) / Double(safeColumns)) - 0.5
                let rayAngle = baseAngle + (cameraOffset * fieldOfView)
                let sampleX = originX + (cos(rayAngle) * distance)
                let sampleY = originY + (sin(rayAngle) * distance)
                let level = lightField.level(atWorldX: sampleX, y: sampleY)
                return max(
                    lightField.ambient * 0.82,
                    min(1.0, pow(level, 0.78) + 0.05)
                )
            }
        }

        return DepthFloorLightingSnapshot(
            columns: safeColumns,
            bands: safeBands,
            ambient: lightField.ambient,
            values: values
        )
    }

    private static func makeDepthTileLighting(
        board: MapBoardSnapshot,
        lightField: DepthLightField
    ) -> DepthTileLightingSnapshot {
        let values = board.rows.map { row in
            row.map { cell in
                lightField.effectiveLevel(
                    at: cell.position,
                    shadowWeight: 0.74,
                    minimumAmbientFactor: 0.10
                )
            }
        }
        return DepthTileLightingSnapshot(
            width: board.width,
            height: board.height,
            ambient: lightField.ambient,
            values: values
        )
    }

    private static func makeDepthWorldLighting(lightField: DepthLightField) -> DepthWorldLightingSnapshot {
        DepthWorldLightingSnapshot(
            width: lightField.width,
            height: lightField.height,
            ambient: lightField.ambient,
            subdivisions: lightField.subdivisions,
            sampleWidth: lightField.sampleWidth,
            sampleHeight: lightField.sampleHeight,
            values: lightField.values,
            shadowValues: lightField.shadowValues
        )
    }

    private static func makeBillboard(
        for cell: BoardCellSnapshot,
        distance: Double,
        angleOffset: Double,
        maxDistance: Double,
        lightLevel: Double
    ) -> DepthBillboardSnapshot? {
        switch cell.occupant {
        case .enemy(let id):
            return DepthBillboardSnapshot(
                id: "enemy:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .enemy(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.78,
                widthScale: 0.70,
                lightLevel: lightLevel
            )
        case .npc(let id):
            return DepthBillboardSnapshot(
                id: "npc:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .npc(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.72,
                widthScale: 0.68,
                lightLevel: lightLevel
            )
        case .boss(let id):
            return DepthBillboardSnapshot(
                id: "boss:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .boss(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.84,
                widthScale: 0.82,
                lightLevel: lightLevel
            )
        case .none, .player:
            break
        }

        if cell.feature != .none {
            let appearance = featureAppearance(for: cell.feature)
            return DepthBillboardSnapshot(
                id: "feature:\(cell.position.x):\(cell.position.y):\(cell.feature.debugName)",
                kind: .feature(cell.feature),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: appearance.scale,
                widthScale: appearance.widthScale,
                lightLevel: lightLevel
            )
        }

        guard let tileAppearance = tileBillboardAppearance(for: cell.tile.type) else {
            return nil
        }
        return DepthBillboardSnapshot(
            id: "tile:\(cell.position.x):\(cell.position.y):\(cell.tile.type.rawValue)",
            kind: .tile(cell.tile.type),
            distance: distance,
            angleOffset: angleOffset,
            maxDistance: maxDistance,
            scale: tileAppearance.scale,
            widthScale: tileAppearance.widthScale,
            lightLevel: lightLevel
        )
    }

    private static func featureAppearance(for feature: MapFeature) -> (scale: Double, widthScale: Double) {
        switch feature {
        case .none:
            return (0.0, 0.0)
        case .chest:
            return (0.44, 0.84)
        case .bed:
            return (0.34, 1.10)
        case .plateUp:
            return (0.22, 1.30)
        case .plateDown:
            return (0.16, 1.45)
        case .switchIdle, .switchLit:
            return (0.28, 0.84)
        case .torchFloor:
            return (0.36, 0.82)
        case .torchWall:
            return (0.42, 0.76)
        case .shrine:
            return (0.46, 0.90)
        case .beacon:
            return (0.54, 0.92)
        case .gate:
            return (0.62, 1.05)
        }
    }

    private static func tileBillboardAppearance(for tileType: TileType) -> (scale: Double, widthScale: Double)? {
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

    private static func depthRenderProfile(for mapID: String, usesSkyBackdrop: Bool) -> DepthRenderProfile {
        let tightIndoorFragments = [
            "barrow",
            "catacomb",
            "crypt",
            "vault",
            "sanctum",
            "archive"
        ]
        let tightIndoor = tightIndoorFragments.contains { mapID.contains($0) }

        if tightIndoor {
            return DepthRenderProfile(
                fieldOfView: .pi / 3.4,
                maxDistance: 8.5,
                columns: 96,
                ambientLight: 0.11,
                lightSubdivisions: 12,
                floorLightBands: 20
            )
        }
        if usesSkyBackdrop {
            return DepthRenderProfile(
                fieldOfView: .pi / 2.95,
                maxDistance: 12.0,
                columns: 128,
                ambientLight: 0.18,
                lightSubdivisions: 12,
                floorLightBands: 22
            )
        }
        return DepthRenderProfile(
            fieldOfView: defaultDepthFieldOfView,
            maxDistance: 10.0,
            columns: 112,
            ambientLight: 0.15,
            lightSubdivisions: 12,
            floorLightBands: 20
        )
    }

    private static func makeDepthLightField(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double,
        subdivisions: Int
    ) -> DepthLightField {
        guard board.width > 0, board.height > 0 else {
            return DepthLightField(
                width: board.width,
                height: board.height,
                ambient: ambient,
                subdivisions: max(1, subdivisions),
                sampleWidth: 0,
                sampleHeight: 0,
                values: [],
                shadowValues: []
            )
        }

        let staticKey = staticLightCacheKey(
            from: state,
            board: board,
            ambient: ambient,
            subdivisions: subdivisions
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
                sources: staticSources,
                board: board
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
        applyLightSource(lantern, lightValues: &values, shadowValues: &shadowValues, field: staticField, board: board)
        shadowValues = softenedShadowMask(shadowValues)
        let finalField = DepthLightField(
            width: board.width,
            height: board.height,
            ambient: ambient,
            subdivisions: staticField.subdivisions,
            sampleWidth: staticField.sampleWidth,
            sampleHeight: staticField.sampleHeight,
            values: values,
            shadowValues: shadowValues
        )
        cachedFinalLightField = (finalKey, finalField)
        return finalField
    }

    private static func isLanternDepthLightEnabled(for state: GameState) -> Bool {
        // Lantern light in Depth3D is opt-in; default runs should rely on world lights.
        state.world.openedInteractables.contains("lantern_enabled")
    }

    private static func staticLightCacheKey(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double,
        subdivisions: Int
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
            openedInteractablesHash: openedInteractablesHash,
            bossStateHash: bossStateHash
        )
    }

    private static func hashStrings<S: Sequence>(_ values: S) -> Int where S.Element == String {
        var hasher = Hasher()
        let sorted = Array(values).sorted()
        for value in sorted {
            hasher.combine(value)
        }
        return hasher.finalize()
    }

    private static func playerLanternLightSource(for player: PlayerState) -> DepthLightSource {
        let lanternStrength = max(0.0, min(1.0, Double(player.effectiveLanternCapacity()) / 18.0))
        return DepthLightSource(
            position: player.position,
            intensity: 0.22 + (lanternStrength * 0.22),
            radius: 2.8 + (lanternStrength * 2.4),
            blockedTransmission: 0.10 + (lanternStrength * 0.06),
            shadowStrength: 0.14 + (lanternStrength * 0.12)
        )
    }

    private static func buildLightField(
        width: Int,
        height: Int,
        ambient: Double,
        subdivisions: Int,
        sources: [DepthLightSource],
        board: MapBoardSnapshot
    ) -> DepthLightField {
        let sampleScale = max(1, subdivisions)
        let sampleWidth = max(0, width * sampleScale)
        let sampleHeight = max(0, height * sampleScale)
        var values = Array(
            repeating: Array(repeating: ambient, count: sampleWidth),
            count: sampleHeight
        )
        var shadowValues = Array(
            repeating: Array(repeating: 0.0, count: sampleWidth),
            count: sampleHeight
        )
        let field = DepthLightField(
            width: width,
            height: height,
            ambient: ambient,
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
                board: board
            )
        }
        shadowValues = softenedShadowMask(shadowValues)
        return DepthLightField(
            width: width,
            height: height,
            ambient: ambient,
            subdivisions: sampleScale,
            sampleWidth: sampleWidth,
            sampleHeight: sampleHeight,
            values: values,
            shadowValues: shadowValues
        )
    }

    private static func applyLightSource(
        _ source: DepthLightSource,
        lightValues: inout [[Double]],
        shadowValues: inout [[Double]],
        field: DepthLightField,
        board: MapBoardSnapshot
    ) {
        guard board.width > 0,
              board.height > 0,
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
                    board: board
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

    private static func softenedShadowMask(_ values: [[Double]]) -> [[Double]] {
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

    private static func collectDepthLightSources(from state: GameState, board: MapBoardSnapshot) -> [DepthLightSource] {
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

    private static func depthLightSource(for cell: BoardCellSnapshot) -> DepthLightSource? {
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

    private static func hasLightLineOfSight(
        fromWorldX startX: Double,
        y startY: Double,
        toWorldX endX: Double,
        y endY: Double,
        board: MapBoardSnapshot
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
                    board: board
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
                    board: board
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
                    board: board
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
                    board: board
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
                    board: board
                ) {
                    return false
                }
            }
        }

        return true
    }

    private static func isBlockingLightTile(
        x: Int,
        y: Int,
        startX: Int,
        startY: Int,
        endX: Int,
        endY: Int,
        board: MapBoardSnapshot
    ) -> Bool {
        if (x == startX && y == startY) || (x == endX && y == endY) {
            return false
        }

        guard let cell = board.cell(at: Position(x: x, y: y)) else {
            return true
        }
        return !cell.tile.walkable
    }

    private static func resolved(_ raw: Character, state: GameState) -> Character {
        if raw == "+", state.quests.has(.barrowUnlocked) {
            return "/"
        }
        return raw
    }

    private static func occupant(at position: Position, state: GameState) -> MapOccupant {
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

    private static func feature(at position: Position, state: GameState) -> MapFeature {
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

    private static func usesSkyBackdrop(for mapID: String) -> Bool {
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

    private static func facingAngle(for direction: Direction) -> Double {
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
}
