import Foundation

struct DepthFloorProjectionKey: Hashable {
    let width: Int
    let height: Int
    let horizonOffset: Int
    let floorBands: Int
    let facing: Int
    let fieldOfViewMilli: Int
}

struct DepthFloorStripProjection {
    let x0: Double
    let x1: Double
    let xNormalized: Double
    let rayX: Double
    let rayY: Double
}

struct DepthFloorBandProjection {
    let y0: Double
    let y1: Double
    let rowDistance: Double
    let bandNorm: Double
    let strips: [DepthFloorStripProjection]
}

struct DepthBillboardProjection {
    let centerX: Double
    let left: Double
    let top: Double
    let width: Double
    let height: Double
}

enum DepthStripLightingMode {
    case raw
    case effective
}

enum DepthProjectionMath {
    private static let wallProjectionScale = 0.82
    private static let cameraHeight = 0.5

    static func facingUnitVector(for direction: Direction) -> (x: Double, y: Double) {
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

    static func rightUnitVector(for direction: Direction) -> (x: Double, y: Double) {
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

    static func facingKey(for direction: Direction) -> Int {
        switch direction {
        case .up:
            return 0
        case .right:
            return 1
        case .down:
            return 2
        case .left:
            return 3
        }
    }

    static func floorProjection(
        width: Int,
        height: Int,
        horizonOffset: Int,
        floorBands: Int,
        facing: Direction,
        fieldOfView: Double,
        stripDensity: Double = 0.60,
        minStrips: Int = 96,
        maxStrips: Int = 384,
        bandExponent: Double = 1.58
    ) -> [DepthFloorBandProjection] {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        let safeBands = max(1, floorBands)
        let horizon = Double(max(0, min(height, horizonOffset)))
        let totalFloorHeight = max(1.0, Double(safeHeight) - horizon)
        let forward = facingUnitVector(for: facing)
        let right = rightUnitVector(for: facing)
        let planeScale = tan(fieldOfView * 0.5)
        let leftRay = (
            x: forward.x - (right.x * planeScale),
            y: forward.y - (right.y * planeScale)
        )
        let rightRay = (
            x: forward.x + (right.x * planeScale),
            y: forward.y + (right.y * planeScale)
        )
        let posZ = Double(safeHeight) * wallProjectionScale * cameraHeight
        var result: [DepthFloorBandProjection] = []
        result.reserveCapacity(safeBands)

        for band in 0..<safeBands {
            let t0 = Double(band) / Double(safeBands)
            let t1 = Double(band + 1) / Double(safeBands)
            let y0 = horizon + (totalFloorHeight * pow(t0, bandExponent))
            let y1 = horizon + (totalFloorHeight * pow(t1, bandExponent))
            let rowScreenY = max(horizon + 1.0, (y0 + y1) * 0.5)
            let rowDepth = max(1.0, rowScreenY - horizon)
            let rowDistance = posZ / rowDepth
            let bandNorm = (Double(band) + 0.5) / Double(safeBands)
            let stripScale = 0.78 + (pow(1.0 - bandNorm, 1.2) * 0.72)
            let requestedStrips = Int((Double(safeWidth) * stripDensity) * stripScale)
            let stripCount = min(maxStrips, max(minStrips, requestedStrips))
            var strips: [DepthFloorStripProjection] = []
            strips.reserveCapacity(stripCount)

            for strip in 0..<stripCount {
                let xNormalized = (Double(strip) + 0.5) / Double(stripCount)
                let rayX = leftRay.x + ((rightRay.x - leftRay.x) * xNormalized)
                let rayY = leftRay.y + ((rightRay.y - leftRay.y) * xNormalized)
                let x0 = (Double(strip) / Double(stripCount)) * Double(safeWidth)
                let x1 = (Double(strip + 1) / Double(stripCount)) * Double(safeWidth)
                strips.append(
                    DepthFloorStripProjection(
                        x0: x0,
                        x1: x1,
                        xNormalized: xNormalized,
                        rayX: rayX,
                        rayY: rayY
                    )
                )
            }

            result.append(
                DepthFloorBandProjection(
                    y0: y0,
                    y1: y1,
                    rowDistance: rowDistance,
                    bandNorm: bandNorm,
                    strips: strips
                )
            )
        }

        return result
    }

    static func billboardProjection(
        screenWidth: Double,
        screenHeight: Double,
        horizon: Double,
        fieldOfView: Double,
        billboard: DepthBillboardSnapshot,
        aspectRatio: Double
    ) -> DepthBillboardProjection {
        let centerX = ((billboard.angleOffset / fieldOfView) + 0.5) * screenWidth
        let projectedHeight = min(
            screenHeight * 0.88,
            (screenHeight * billboard.scale) / max(0.16, billboard.distance)
        )
        let projectedWidth = max(10.0, projectedHeight * max(0.10, aspectRatio) * billboard.widthScale)
        return DepthBillboardProjection(
            centerX: centerX,
            left: centerX - (projectedWidth * 0.5),
            top: horizon - (projectedHeight * 0.5),
            width: projectedWidth,
            height: projectedHeight
        )
    }

    static func smoothStripLevels(_ values: inout [Double]) {
        guard values.count >= 3 else {
            return
        }

        let source = values
        for index in source.indices {
            let left = source[max(0, index - 1)]
            let center = source[index]
            let right = source[min(source.count - 1, index + 1)]
            values[index] = (left * 0.24) + (center * 0.52) + (right * 0.24)
        }
    }

    static func sampleStripLighting(
        band: DepthFloorBandProjection,
        playerX: Double,
        playerY: Double,
        worldLighting: DepthWorldLightingSnapshot?,
        floorLighting: DepthFloorLightingSnapshot?,
        mode: DepthStripLightingMode,
        shadowWeight: Double = 0.72,
        minimumAmbientFactor: Double = 0.10
    ) -> ([Double], [Double]) {
        let ambient = worldLighting?.ambient ?? floorLighting?.ambient ?? 0.20
        var stripLevels = Array(repeating: ambient, count: band.strips.count)
        var stripShadowLevels = Array(repeating: 0.0, count: band.strips.count)

        for (index, strip) in band.strips.enumerated() {
            let worldX = playerX + (band.rowDistance * strip.rayX)
            let worldY = playerY + (band.rowDistance * strip.rayY)
            let rawLevel = worldLighting?.level(atWorldX: worldX, y: worldY)
                ?? floorLighting?.interpolatedLevel(xNormalized: strip.xNormalized, yNormalized: band.bandNorm)
                ?? ambient
            let shadowLevel = worldLighting?.shadowLevel(atWorldX: worldX, y: worldY)
                ?? floorLighting?.interpolatedShadow(xNormalized: strip.xNormalized, yNormalized: band.bandNorm)
                ?? 0.0

            switch mode {
            case .raw:
                stripLevels[index] = rawLevel
            case .effective:
                let excess = max(0.0, rawLevel - ambient)
                let shaded = ambient + max(0.0, excess - (shadowLevel * shadowWeight))
                let minimum = max(0.01, ambient * minimumAmbientFactor)
                stripLevels[index] = max(minimum, min(1.0, shaded))
            }
            stripShadowLevels[index] = shadowLevel
        }

        smoothStripLevels(&stripLevels)
        return (stripLevels, stripShadowLevels)
    }
}
