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

struct DepthSceneSnapshot {
    let facing: Direction
    let fieldOfView: Double
    let maxDistance: Double
    let usesSkyBackdrop: Bool
    let samples: [DepthRaySample]
    let billboards: [DepthBillboardSnapshot]
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
    }

    private struct DepthLightSource {
        let position: Position
        let intensity: Double
        let radius: Double
    }

    private struct DepthLightField {
        let width: Int
        let height: Int
        let ambient: Double
        let values: [[Double]]

        func level(at position: Position) -> Double {
            guard position.x >= 0,
                  position.y >= 0,
                  position.x < width,
                  position.y < height else {
                return ambient
            }
            return values[position.y][position.x]
        }
    }

    private struct DepthStaticLightCacheKey: Hashable {
        let mapID: String
        let width: Int
        let height: Int
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
            ambient: profile.ambientLight
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

        return DepthSceneSnapshot(
            facing: state.player.facing,
            fieldOfView: profile.fieldOfView,
            maxDistance: profile.maxDistance,
            usesSkyBackdrop: skyBackdrop,
            samples: samples,
            billboards: billboards
        )
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
                    lightLevel: lightField.level(at: cell.position)
                ) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
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
                ambientLight: 0.16
            )
        }
        if usesSkyBackdrop {
            return DepthRenderProfile(
                fieldOfView: .pi / 2.95,
                maxDistance: 12.0,
                columns: 128,
                ambientLight: 0.36
            )
        }
        return DepthRenderProfile(
            fieldOfView: defaultDepthFieldOfView,
            maxDistance: 10.0,
            columns: 112,
            ambientLight: 0.24
        )
    }

    private static func makeDepthLightField(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double
    ) -> DepthLightField {
        guard board.width > 0, board.height > 0 else {
            return DepthLightField(width: board.width, height: board.height, ambient: ambient, values: [])
        }

        let staticKey = staticLightCacheKey(from: state, board: board, ambient: ambient)
        let staticField: DepthLightField
        if let cached = cachedStaticLightField, cached.key == staticKey {
            staticField = cached.field
        } else {
            let staticSources = collectDepthLightSources(from: state, board: board)
            staticField = buildLightField(
                width: board.width,
                height: board.height,
                ambient: ambient,
                sources: staticSources,
                board: board
            )
            cachedStaticLightField = (staticKey, staticField)
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
        applyLightSource(lantern, to: &values, board: board)
        let finalField = DepthLightField(
            width: board.width,
            height: board.height,
            ambient: ambient,
            values: values
        )
        cachedFinalLightField = (finalKey, finalField)
        return finalField
    }

    private static func staticLightCacheKey(
        from state: GameState,
        board: MapBoardSnapshot,
        ambient: Double
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
            intensity: 0.34 + (lanternStrength * 0.34),
            radius: 3.2 + (lanternStrength * 3.0)
        )
    }

    private static func buildLightField(
        width: Int,
        height: Int,
        ambient: Double,
        sources: [DepthLightSource],
        board: MapBoardSnapshot
    ) -> DepthLightField {
        var values = Array(
            repeating: Array(repeating: ambient, count: width),
            count: height
        )
        for source in sources {
            applyLightSource(source, to: &values, board: board)
        }
        return DepthLightField(
            width: width,
            height: height,
            ambient: ambient,
            values: values
        )
    }

    private static func applyLightSource(
        _ source: DepthLightSource,
        to values: inout [[Double]],
        board: MapBoardSnapshot
    ) {
        guard board.width > 0, board.height > 0 else { return }

        let minX = max(0, Int(floor(Double(source.position.x) - source.radius)))
        let maxX = min(board.width - 1, Int(ceil(Double(source.position.x) + source.radius)))
        let minY = max(0, Int(floor(Double(source.position.y) - source.radius)))
        let maxY = min(board.height - 1, Int(ceil(Double(source.position.y) + source.radius)))

        for y in minY...maxY {
            for x in minX...maxX {
                let target = Position(x: x, y: y)
                let dx = Double(source.position.x - target.x)
                let dy = Double(source.position.y - target.y)
                let distance = hypot(dx, dy)
                if distance > source.radius {
                    continue
                }

                let attenuation = pow(max(0.0, 1.0 - (distance / source.radius)), 1.75)
                var contribution = source.intensity * attenuation
                if !hasLightLineOfSight(from: source.position, to: target, board: board) {
                    contribution *= 0.24
                }
                values[y][x] = max(0.05, min(1.0, values[y][x] + contribution))
            }
        }
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
                        radius: 2.6
                    )
                )
            }
        }

        return sources
    }

    private static func depthLightSource(for cell: BoardCellSnapshot) -> DepthLightSource? {
        switch cell.feature {
        case .beacon:
            return DepthLightSource(position: cell.position, intensity: 0.90, radius: 8.2)
        case .shrine:
            return DepthLightSource(position: cell.position, intensity: 0.58, radius: 5.2)
        case .switchLit:
            return DepthLightSource(position: cell.position, intensity: 0.30, radius: 3.4)
        case .torchFloor:
            return DepthLightSource(position: cell.position, intensity: 0.42, radius: 3.8)
        case .torchWall:
            return DepthLightSource(position: cell.position, intensity: 0.36, radius: 3.2)
        case .gate:
            return DepthLightSource(position: cell.position, intensity: 0.16, radius: 2.1)
        case .none, .chest, .bed, .plateUp, .plateDown, .switchIdle:
            break
        }

        switch cell.tile.type {
        case .doorOpen:
            return DepthLightSource(position: cell.position, intensity: 0.22, radius: 2.6)
        case .beacon:
            return DepthLightSource(position: cell.position, intensity: 0.74, radius: 6.8)
        default:
            break
        }

        switch cell.occupant {
        case .boss:
            return DepthLightSource(position: cell.position, intensity: 0.28, radius: 3.3)
        case .none, .player, .npc, .enemy:
            return nil
        }
    }

    private static func hasLightLineOfSight(from start: Position, to end: Position, board: MapBoardSnapshot) -> Bool {
        if start == end {
            return true
        }

        var x0 = start.x
        var y0 = start.y
        let x1 = end.x
        let y1 = end.y

        let dx = abs(x1 - x0)
        let dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var error = dx - dy

        while x0 != x1 || y0 != y1 {
            let e2 = error * 2
            if e2 > -dy {
                error -= dy
                x0 += sx
            }
            if e2 < dx {
                error += dx
                y0 += sy
            }

            if x0 == x1, y0 == y1 {
                break
            }

            let position = Position(x: x0, y: y0)
            guard let cell = board.cell(at: position) else {
                return false
            }
            if !cell.tile.walkable {
                return false
            }
        }

        return true
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
