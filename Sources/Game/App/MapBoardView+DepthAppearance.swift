#if canImport(AppKit)
import Foundation
import SwiftUI

extension MapBoardView {
    func depthFeatureAppearance(
        for feature: MapFeature
    ) -> (pattern: [[Int]], color: Color, scale: Double, widthScale: CGFloat)? {
        let fallback: (pattern: [[Int]], color: Color, scale: Double, widthScale: CGFloat)?
        switch feature {
        case .none:
            fallback = nil
        case .chest:
            fallback = (
                [
                    [1, 1, 1],
                    [1, 0, 1],
                ],
                palette.lightGold,
                0.44,
                0.84
            )
        case .bed:
            fallback = (
                [
                    [1, 1, 1],
                    [1, 0, 0],
                ],
                palette.text,
                0.34,
                1.10
            )
        case .plateUp:
            fallback = (
                [
                    [1, 1],
                    [1, 1],
                ],
                palette.accentViolet,
                0.22,
                1.30
            )
        case .plateDown:
            fallback = (
                [
                    [1, 1],
                ],
                palette.text.opacity(0.65),
                0.16,
                1.45
            )
        case .switchIdle:
            fallback = (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [0, 1, 0],
                ],
                palette.accentBlue,
                0.28,
                0.84
            )
        case .switchLit:
            fallback = (
                [
                    [1, 1, 1],
                    [1, 1, 1],
                    [1, 1, 1],
                ],
                palette.lightGold,
                0.28,
                0.84
            )
        case .torchFloor:
            fallback = (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [0, 1, 0],
                    [0, 1, 0],
                ],
                palette.titleGold,
                0.36,
                0.82
            )
        case .torchWall:
            fallback = (
                [
                    [1, 1, 1],
                    [0, 1, 0],
                    [1, 1, 1],
                    [0, 1, 0],
                ],
                palette.lightGold,
                0.42,
                0.76
            )
        case .shrine:
            fallback = (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [0, 1, 0],
                ],
                regionTheme.shrine,
                0.46,
                0.90
            )
        case .beacon:
            fallback = (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [1, 1, 1],
                ],
                regionTheme.beacon,
                0.54,
                0.92
            )
        case .gate:
            fallback = (
                [
                    [1, 0, 1],
                    [1, 0, 1],
                    [1, 1, 1],
                ],
                regionTheme.doorLocked,
                0.62,
                1.05
            )
        }

        guard let fallback else {
            return nil
        }

        if let override = GraphicsAssetCatalog.featureSprite(for: feature.debugName) {
            let pattern = override.pattern?.rows ?? fallback.pattern
            let color = override.color.map(Self.swiftUIColor(from:)) ?? fallback.color
            return (pattern, color, fallback.scale, fallback.widthScale)
        }
        return fallback
    }

    func depthBillboardPattern(for kind: DepthBillboardKind) -> [[Int]] {
        switch kind {
        case .npc(let id):
            return firstPersonNPCPattern(for: id)
        case .enemy(let id):
            return firstPersonEnemyPattern(for: id)
        case .boss(let id):
            return GraphicsAssetCatalog.occupantSprite(for: "boss")?.pattern?.rows
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows
                ?? [
                    [1, 0, 1],
                    [1, 1, 1],
                    [1, 1, 1],
                ]
        case .feature(let feature):
            return depthFeatureAppearance(for: feature)?.pattern ?? [[1]]
        case .tile(let tileType):
            return depthTileAppearance(for: tileType).pattern
        }
    }

    func depthBillboardColor(for kind: DepthBillboardKind) -> Color {
        switch kind {
        case .npc(let id):
            return firstPersonNPCColor(for: id)
        case .enemy(let id):
            return firstPersonEnemyColor(for: id)
        case .boss(let id):
            return GraphicsAssetCatalog.occupantSprite(for: "boss")?.color.map(Self.swiftUIColor(from:))
                ?? GraphicsAssetCatalog.enemySprite(for: id)?.color.map(Self.swiftUIColor(from:))
                ?? palette.accentViolet
        case .feature(let feature):
            return depthFeatureAppearance(for: feature)?.color ?? palette.text
        case .tile(let tileType):
            return depthTileAppearance(for: tileType).color
        }
    }

    func depthTileAppearance(for tileType: TileType) -> (pattern: [[Int]], color: Color) {
        switch tileType {
        case .stairs:
            return (
                [
                    [1, 1, 1, 1],
                    [1, 0, 0, 0],
                    [1, 1, 1, 0],
                ],
                regionTheme.stairs
            )
        case .doorOpen:
            return (
                [
                    [1, 0, 1],
                    [1, 0, 1],
                    [1, 1, 1],
                ],
                regionTheme.doorOpen
            )
        case .brush:
            return (
                [
                    [1, 0, 1, 0],
                    [0, 1, 0, 1],
                    [1, 0, 1, 0],
                ],
                regionTheme.brush
            )
        case .shrine:
            return (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [0, 1, 0],
                ],
                regionTheme.shrine
            )
        case .beacon:
            return (
                [
                    [0, 1, 0],
                    [1, 1, 1],
                    [1, 1, 1],
                ],
                regionTheme.beacon
            )
        case .floor, .wall, .water, .doorLocked:
            return (
                [
                    [1],
                ],
                palette.text
            )
        }
    }

    func sideWallColor(for tile: Tile, theme: RegionTheme, brightness: Double) -> Color {
        frontWallColor(for: tile, theme: theme).opacity(max(0.28, brightness))
    }

    func frontWallColor(for tile: Tile, theme: RegionTheme) -> Color {
        switch tile.type {
        case .floor:
            return theme.floor
        case .wall:
            return theme.wall
        case .water:
            return theme.water
        case .brush:
            return theme.brush
        case .doorLocked:
            return theme.doorLocked
        case .doorOpen:
            return theme.doorOpen
        case .shrine:
            return theme.shrine
        case .stairs:
            return theme.stairs
        case .beacon:
            return theme.beacon
        }
    }

    func firstPersonNPCPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.npcSprite(for: id)?.pattern?.rows {
            return pattern
        }
        switch id {
        case "elder":
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 0, 1],
            ]
        case "field_scout":
            return [
                [1, 0, 1],
                [0, 1, 0],
                [0, 1, 0],
            ]
        case "orchard_guide":
            return [
                [0, 1, 0],
                [1, 1, 0],
                [0, 1, 1],
            ]
        default:
            return [
                [0, 1, 0],
                [1, 1, 1],
                [0, 1, 0],
            ]
        }
    }

    func firstPersonNPCColor(for id: String) -> Color {
        if let color = GraphicsAssetCatalog.npcSprite(for: id)?.color {
            return Self.swiftUIColor(from: color)
        }
        switch id {
        case "elder":
            return palette.accentBlue
        case "field_scout":
            return palette.text
        case "orchard_guide":
            return palette.accentGreen
        case "barrow_scholar":
            return palette.accentViolet
        default:
            return palette.lightGold
        }
    }

    func firstPersonEnemyPattern(for id: String) -> [[Int]] {
        if let pattern = GraphicsAssetCatalog.enemySprite(for: id)?.pattern?.rows {
            return pattern
        }
        if id.hasPrefix("crow") {
            return [
                [1, 0, 1],
                [1, 1, 1],
                [0, 1, 0],
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1, 1, 0],
                [1, 1, 1],
                [0, 1, 1],
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0, 1, 0],
                [1, 1, 1],
                [1, 1, 1],
            ]
        }
        return [
            [1, 1, 1],
            [1, 0, 1],
            [1, 1, 1],
        ]
    }

    func firstPersonEnemyColor(for id: String) -> Color {
        if let color = GraphicsAssetCatalog.enemySprite(for: id)?.color {
            return Self.swiftUIColor(from: color)
        }
        if id.hasPrefix("crow") {
            return palette.titleGold
        }
        if id.hasPrefix("hound") {
            return palette.accentGreen
        }
        if id.hasPrefix("wraith") {
            return palette.accentViolet
        }
        return palette.titleGold
    }
}
#endif
