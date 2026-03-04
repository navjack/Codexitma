import CoreGraphics
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
}

struct DepthSceneSnapshot {
    let facing: Direction
    let fieldOfView: Double
    let maxDistance: Double
    let usesSkyBackdrop: Bool
    let samples: [DepthRaySample]
    let billboards: [DepthBillboardSnapshot]
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
}

enum GraphicsSceneSnapshotBuilder {
    private static let depthFieldOfView = Double.pi / 3.1
    private static let depthDrawDistance = 9.0
    private static let depthColumns = 96

    static func build(state: GameState, visualTheme: GraphicsVisualTheme) -> GraphicsSceneSnapshot {
        let board = makeBoard(from: state)
        let depth = visualTheme == .depth3D ? makeDepthScene(from: state, board: board) : nil
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
            questFlow: state.questFlow
        )
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
        let origin = CGPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let caster = DepthRaycaster(
            origin: origin,
            facing: state.player.facing,
            fov: depthFieldOfView
        ) { position in
            board.cell(at: position)?.tile ?? TileFactory.tile(for: "#")
        }

        let samples = caster.castSamples(columns: depthColumns, maxDistance: depthDrawDistance)
        let billboards = makeDepthBillboards(from: state, board: board)
            .sorted { $0.distance > $1.distance }

        return DepthSceneSnapshot(
            facing: state.player.facing,
            fieldOfView: depthFieldOfView,
            maxDistance: depthDrawDistance,
            usesSkyBackdrop: usesSkyBackdrop(for: state.player.currentMapID),
            samples: samples,
            billboards: billboards
        )
    }

    private static func makeDepthBillboards(from state: GameState, board: MapBoardSnapshot) -> [DepthBillboardSnapshot] {
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
                if distance > depthDrawDistance {
                    continue
                }

                let angleOffset = atan2(sideDistance, forwardDistance)
                if abs(angleOffset) > (depthFieldOfView * 0.65) {
                    continue
                }

                if let billboard = makeBillboard(for: cell, distance: distance, angleOffset: angleOffset) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
    }

    private static func makeBillboard(
        for cell: BoardCellSnapshot,
        distance: Double,
        angleOffset: Double
    ) -> DepthBillboardSnapshot? {
        switch cell.occupant {
        case .enemy(let id):
            return DepthBillboardSnapshot(
                id: "enemy:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .enemy(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: depthDrawDistance,
                scale: 0.78,
                widthScale: 0.70
            )
        case .npc(let id):
            return DepthBillboardSnapshot(
                id: "npc:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .npc(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: depthDrawDistance,
                scale: 0.72,
                widthScale: 0.68
            )
        case .boss(let id):
            return DepthBillboardSnapshot(
                id: "boss:\(id):\(cell.position.x):\(cell.position.y)",
                kind: .boss(id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: depthDrawDistance,
                scale: 0.84,
                widthScale: 0.82
            )
        case .none, .player:
            break
        }

        guard cell.feature != .none else {
            return nil
        }

        let appearance = featureAppearance(for: cell.feature)
        return DepthBillboardSnapshot(
            id: "feature:\(cell.position.x):\(cell.position.y):\(cell.feature.debugName)",
            kind: .feature(cell.feature),
            distance: distance,
            angleOffset: angleOffset,
            maxDistance: depthDrawDistance,
            scale: appearance.scale,
            widthScale: appearance.widthScale
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
        case .shrine:
            return (0.46, 0.90)
        case .beacon:
            return (0.54, 0.92)
        case .gate:
            return (0.62, 1.05)
        }
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
