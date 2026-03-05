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

struct PauseOptionSnapshot {
    let index: Int
    let label: String
    let detail: String
    let isSelected: Bool
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
    let pauseOptions: [PauseOptionSnapshot]
    let pauseDetail: String?
}

enum GraphicsSceneSnapshotBuilder {
    static let defaultDepthFieldOfView = Double.pi / 3.1

    struct DepthRenderProfile {
        let fieldOfView: Double
        let maxDistance: Double
        let columns: Int
        let ambientLight: Double
        let skyEmissive: Double
        let lightSubdivisions: Int
        let floorLightBands: Int
    }

    struct DepthLightSource {
        let position: Position
        let intensity: Double
        let radius: Double
        let blockedTransmission: Double
        let shadowStrength: Double
    }

    struct DepthLightField {
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

    struct DepthStaticLightCacheKey: Hashable {
        let mapID: String
        let width: Int
        let height: Int
        let subdivisions: Int
        let ambientBucket: Int
        let skyEmissiveBucket: Int
        let openedInteractablesHash: Int
        let bossStateHash: Int
    }

    struct DepthFinalLightCacheKey: Hashable {
        let staticKey: DepthStaticLightCacheKey
        let playerPosition: Position
        let lanternBucket: Int
    }

    nonisolated(unsafe) static var cachedStaticLightField: (key: DepthStaticLightCacheKey, field: DepthLightField)?
    nonisolated(unsafe) static var cachedFinalLightField: (key: DepthFinalLightCacheKey, field: DepthLightField)?
}
