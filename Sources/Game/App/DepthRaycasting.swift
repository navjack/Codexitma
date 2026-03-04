#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

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

#endif
