import Foundation

extension GraphicsSceneSnapshotBuilder {
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
            shopDetail: state.shopDetail,
            pauseOptions: pauseOptions(from: state),
            pauseDetail: pauseDetail(from: state)
        )
    }

    static func traitSummaryLine(_ traits: TraitProfile) -> String {
        "\(TraitStat.brawn.shortLabel):\(traits.brawn) \(TraitStat.agility.shortLabel):\(traits.agility) \(TraitStat.grit.shortLabel):\(traits.grit)"
    }

    static func traitSummaryLineSecondary(_ traits: TraitProfile) -> String {
        "\(TraitStat.wits.shortLabel):\(traits.wits) \(TraitStat.lore.shortLabel):\(traits.lore) \(TraitStat.spark.shortLabel):\(traits.spark)"
    }

    static func inventoryEntries(from state: GameState) -> [InventoryEntrySnapshot] {
        state.player.inventory.enumerated().map { index, item in
            InventoryEntrySnapshot(
                index: index,
                name: item.name,
                isSelected: index == state.inventorySelectionIndex,
                isEquipped: EquipmentSlot.allCases.contains { state.player.equipment.itemID(for: $0) == item.id }
            )
        }
    }

    static func inventoryDetail(from state: GameState) -> String? {
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

    static func shopOffers(from state: GameState) -> [ShopOfferSnapshot] {
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

    static func pauseOptions(from state: GameState) -> [PauseOptionSnapshot] {
        PauseMenuOption.allCases.enumerated().map { index, option in
            PauseOptionSnapshot(
                index: index,
                label: option.label,
                detail: option.detail,
                isSelected: index == state.pauseSelectionIndex
            )
        }
    }

    static func pauseDetail(from state: GameState) -> String? {
        guard state.mode == .pause else {
            return nil
        }
        return state.selectedPauseOption().detail
    }

    static func makeBoard(from state: GameState) -> MapBoardSnapshot {
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

    static func makeDepthScene(from state: GameState, board: MapBoardSnapshot) -> DepthSceneSnapshot {
        let mapID = state.player.currentMapID
        let backdrop = depthBackdropStyle(for: state, mapID: mapID)
        let skyBackdrop = backdrop == .sky
        let profile = depthRenderProfile(for: mapID, backdrop: backdrop)
        let lightField = makeDepthLightField(
            from: state,
            board: board,
            ambient: profile.ambientLight,
            subdivisions: profile.lightSubdivisions,
            skyEmissive: profile.skyEmissive
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

    static func makeMapLighting(from state: GameState, board: MapBoardSnapshot) -> DepthTileLightingSnapshot? {
        guard board.width > 0, board.height > 0 else {
            return nil
        }
        let mapID = state.player.currentMapID
        let backdrop = depthBackdropStyle(for: state, mapID: mapID)
        let profile = depthRenderProfile(for: mapID, backdrop: backdrop)
        let lightField = makeDepthLightField(
            from: state,
            board: board,
            ambient: profile.ambientLight,
            subdivisions: profile.lightSubdivisions,
            skyEmissive: profile.skyEmissive
        )
        return makeDepthTileLighting(board: board, lightField: lightField)
    }

    static func makeDepthBillboards(
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

    static func makeDepthFloorLighting(
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

    static func makeDepthTileLighting(
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

    static func makeDepthWorldLighting(lightField: DepthLightField) -> DepthWorldLightingSnapshot {
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

    static func makeBillboard(
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

    static func featureAppearance(for feature: MapFeature) -> (scale: Double, widthScale: Double) {
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

    static func tileBillboardAppearance(for tileType: TileType) -> (scale: Double, widthScale: Double)? {
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

    static func depthRenderProfile(for mapID: String, backdrop: DepthBackdropStyle) -> DepthRenderProfile {
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
                skyEmissive: 0.0,
                lightSubdivisions: 12,
                floorLightBands: 20
            )
        }
        if backdrop == .sky {
            return DepthRenderProfile(
                fieldOfView: .pi / 2.95,
                maxDistance: 12.0,
                columns: 128,
                ambientLight: 0.18,
                skyEmissive: 0.12,
                lightSubdivisions: 12,
                floorLightBands: 22
            )
        }
        return DepthRenderProfile(
            fieldOfView: defaultDepthFieldOfView,
            maxDistance: 10.0,
            columns: 112,
            ambientLight: 0.15,
            skyEmissive: 0.0,
            lightSubdivisions: 12,
            floorLightBands: 20
        )
    }
}
