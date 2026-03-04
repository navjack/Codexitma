import AppKit
import Foundation
import SwiftUI

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

struct CorridorSlice {
    let depth: Int
    let frontTile: Tile
    let leftTile: Tile
    let rightTile: Tile
    let leftBlocked: Bool
    let rightBlocked: Bool
    let frontBlocked: Bool
    let occupant: MapOccupant
    let feature: MapFeature
}

struct PerspectiveFrame {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var width: CGFloat {
        topRight.x - topLeft.x
    }

    var height: CGFloat {
        bottomLeft.y - topLeft.y
    }

    var center: CGPoint {
        CGPoint(x: (topLeft.x + topRight.x) / 2, y: (topLeft.y + bottomLeft.y) / 2)
    }
}

enum DepthHitAxis {
    case none
    case vertical
    case horizontal
}

struct DepthRaySample {
    let column: Int
    let didHit: Bool
    let correctedDistance: Double
    let rawDistance: Double
    let maxDistance: Double
    let hitTile: Tile
    let hitAxis: DepthHitAxis
}

struct DepthBillboard {
    let id: String
    let pattern: [[Int]]
    let color: Color
    let distance: Double
    let angleOffset: Double
    let maxDistance: Double
    let scale: Double
    let widthScale: CGFloat
}

struct DepthRaycaster {
    let origin: CGPoint
    let facing: Direction
    let tileAt: (Position) -> Tile
    let fov: Double

    init(
        origin: CGPoint,
        facing: Direction,
        fov: Double = .pi / 3.1,
        tileAt: @escaping (Position) -> Tile
    ) {
        self.origin = origin
        self.facing = facing
        self.tileAt = tileAt
        self.fov = fov
    }

    func castSamples(columns: Int, maxDistance: Double) -> [DepthRaySample] {
        guard columns > 0 else { return [] }

        return (0..<columns).map { column in
            let cameraOffset = ((Double(column) + 0.5) / Double(columns)) - 0.5
            let rayAngle = baseAngle + (cameraOffset * fov)
            return castRay(column: column, angle: rayAngle, maxDistance: maxDistance)
        }
    }

    private func castRay(column: Int, angle: Double, maxDistance: Double) -> DepthRaySample {
        let originX = Double(origin.x)
        let originY = Double(origin.y)
        let rayX = cos(angle)
        let rayY = sin(angle)

        var mapX = Int(floor(originX))
        var mapY = Int(floor(originY))

        let deltaX = rayX == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / rayX)
        let deltaY = rayY == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / rayY)

        let stepX: Int
        var sideX: Double
        if rayX < 0 {
            stepX = -1
            sideX = (originX - Double(mapX)) * deltaX
        } else {
            stepX = 1
            sideX = (Double(mapX + 1) - originX) * deltaX
        }

        let stepY: Int
        var sideY: Double
        if rayY < 0 {
            stepY = -1
            sideY = (originY - Double(mapY)) * deltaY
        } else {
            stepY = 1
            sideY = (Double(mapY + 1) - originY) * deltaY
        }

        var hitAxis: DepthHitAxis = .none
        var hitTile = TileFactory.tile(for: ".")
        var rawDistance = maxDistance
        var didHit = false
        var travelDistance = 0.0

        while !didHit && travelDistance < maxDistance {
            if sideX < sideY {
                mapX += stepX
                rawDistance = sideX
                sideX += deltaX
                hitAxis = .vertical
            } else {
                mapY += stepY
                rawDistance = sideY
                sideY += deltaY
                hitAxis = .horizontal
            }
            travelDistance = rawDistance

            let tile = tileAt(Position(x: mapX, y: mapY))
            if !tile.walkable {
                hitTile = tile
                didHit = true
                break
            }
        }

        if !didHit {
            return DepthRaySample(
                column: column,
                didHit: false,
                correctedDistance: maxDistance,
                rawDistance: maxDistance,
                maxDistance: maxDistance,
                hitTile: hitTile,
                hitAxis: .none
            )
        }

        let corrected = max(0.05, rawDistance * cos(angle - baseAngle))
        return DepthRaySample(
            column: column,
            didHit: true,
            correctedDistance: corrected,
            rawDistance: rawDistance,
            maxDistance: maxDistance,
            hitTile: hitTile,
            hitAxis: hitAxis
        )
    }

    private var baseAngle: Double {
        switch facing {
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
}
