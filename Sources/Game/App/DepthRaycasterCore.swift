import Foundation

struct DepthPoint {
    let x: Double
    let y: Double
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
    let hitPosition: Position?
    let hitTile: Tile
    let hitAxis: DepthHitAxis
    let lightLevel: Double
}

struct DepthRaycaster {
    let origin: DepthPoint
    let facing: Direction
    let tileAt: (Position) -> Tile
    let lightAt: (Position) -> Double
    let fov: Double

    init(
        origin: DepthPoint,
        facing: Direction,
        fov: Double = .pi / 3.1,
        lightAt: @escaping (Position) -> Double = { _ in 1.0 },
        tileAt: @escaping (Position) -> Tile
    ) {
        self.origin = origin
        self.facing = facing
        self.lightAt = lightAt
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
        let originX = origin.x
        let originY = origin.y
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
                hitPosition: nil,
                hitTile: hitTile,
                hitAxis: .none,
                lightLevel: 1.0
            )
        }

        let hitPosition = Position(x: mapX, y: mapY)
        let lightLevel = max(0.05, min(1.0, lightAt(hitPosition)))
        let corrected = max(0.05, rawDistance * cos(angle - baseAngle))
        return DepthRaySample(
            column: column,
            didHit: true,
            correctedDistance: corrected,
            rawDistance: rawDistance,
            maxDistance: maxDistance,
            hitPosition: hitPosition,
            hitTile: hitTile,
            hitAxis: hitAxis,
            lightLevel: lightLevel
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
