import AppKit
import Foundation
import SwiftUI

struct CrosshairView: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let midX = proxy.size.width / 2
            let midY = proxy.size.height / 2

            Path { path in
                path.move(to: CGPoint(x: midX - 8, y: midY))
                path.addLine(to: CGPoint(x: midX + 8, y: midY))
                path.move(to: CGPoint(x: midX, y: midY - 8))
                path.addLine(to: CGPoint(x: midX, y: midY + 8))
            }
            .stroke(color, lineWidth: 1.5)
        }
    }
}

struct LowResTileView: View {
    let tile: Tile
    let occupant: MapOccupant
    let feature: MapFeature
    let palette: UltimaPalette
    let regionTheme: RegionTheme
    let visualTheme: GraphicsVisualTheme

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(tileColor)
                tilePattern(size: size)
                featureMark(size: size)
                sprite(size: size)
            }
            .overlay(
                Rectangle()
                    .stroke(tileEdgeColor, lineWidth: tile.type == .wall ? 1.6 : 0.6)
            )
        }
    }

    private var tileColor: Color {
        switch tile.type {
        case .floor: return regionTheme.floor
        case .wall: return regionTheme.wall
        case .water: return regionTheme.water
        case .brush: return regionTheme.brush
        case .doorLocked: return regionTheme.doorLocked
        case .doorOpen: return regionTheme.doorOpen
        case .shrine: return regionTheme.shrine
        case .stairs: return regionTheme.stairs
        case .beacon: return regionTheme.beacon
        }
    }

    private var tileEdgeColor: Color {
        if visualTheme == .ultima {
            return Color.black.opacity(0.25)
        }
        if tile.type == .wall {
            return Color.black.opacity(0.65)
        }
        return Color.black.opacity(0.18)
    }

    @ViewBuilder
    private func tilePattern(size: CGFloat) -> some View {
        if visualTheme == .ultima {
            ultimaTilePattern(size: size)
        } else {
            switch tile.type {
            case .floor:
                floorPattern(size: size)
            case .wall:
                ZStack {
                    Rectangle()
                        .fill(regionTheme.roomHighlight.opacity(0.16))
                        .frame(width: size, height: max(2, size * 0.18))
                    Rectangle()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: max(2, size * 0.18), height: size)
                }
            case .water:
                VStack(spacing: max(1, size * 0.08)) {
                    Rectangle().fill(Color.white.opacity(0.20)).frame(width: size * 0.95, height: max(1, size * 0.10))
                    Rectangle().fill(Color.black.opacity(0.18)).frame(width: size * 0.75, height: max(1, size * 0.10))
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.55, height: max(1, size * 0.10))
                }
            case .brush:
                HStack(alignment: .bottom, spacing: max(1, size * 0.08)) {
                    Rectangle().fill(Color.black.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.45)
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.68)
                    Rectangle().fill(Color.black.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.52)
                }
            case .doorLocked, .doorOpen:
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: size * 0.52, height: size * 0.78)
                    Rectangle()
                        .fill(regionTheme.roomHighlight.opacity(0.25))
                        .frame(width: max(1, size * 0.08), height: size * 0.62)
                }
            case .shrine:
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.54, height: size * 0.54)
                    Rectangle().fill(Color.black.opacity(0.15)).frame(width: size * 0.18, height: size * 0.70)
                }
            case .beacon:
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: size * 0.58, height: size * 0.58)
                    Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.18, height: size * 0.82)
                }
            case .stairs:
                VStack(alignment: .trailing, spacing: max(1, size * 0.08)) {
                    Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.32, height: max(1, size * 0.10))
                    Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.52, height: max(1, size * 0.10))
                    Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.72, height: max(1, size * 0.10))
                }
            }
        }
    }

    @ViewBuilder
    private func ultimaTilePattern(size: CGFloat) -> some View {
        switch tile.type {
        case .floor:
            if Int(size).isMultiple(of: 2) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size * 0.24, height: size * 0.24)
                    .offset(x: -size * 0.20, y: -size * 0.18)
            }
        case .wall:
            VStack(spacing: max(1, size * 0.10)) {
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size, height: max(1, size * 0.08))
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: size * 0.72, height: max(1, size * 0.08))
            }
        case .water:
            HStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: size * 0.22, height: size * 0.52)
                Rectangle().fill(Color.white.opacity(0.10)).frame(width: size * 0.22, height: size * 0.34)
            }
        case .brush:
            Rectangle().fill(Color.black.opacity(0.16)).frame(width: size * 0.44, height: size * 0.44)
        case .doorLocked, .doorOpen:
            Rectangle().fill(Color.black.opacity(0.25)).frame(width: size * 0.34, height: size * 0.60)
        case .shrine, .beacon:
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: size * 0.38, height: size * 0.38)
        case .stairs:
            VStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size * 0.28, height: max(1, size * 0.08))
                Rectangle().fill(Color.black.opacity(0.12)).frame(width: size * 0.54, height: max(1, size * 0.08))
            }
        }
    }

    @ViewBuilder
    private func floorPattern(size: CGFloat) -> some View {
        switch regionTheme.pattern {
        case .brick:
            VStack(spacing: max(1, size * 0.14)) {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.12)).frame(width: size, height: max(1, size * 0.08))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).frame(width: size * 0.18)
                    Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.34, height: max(1, size * 0.08))
                    Spacer(minLength: 0)
                    Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.24, height: max(1, size * 0.08))
                }
            }
        case .speckle:
            ZStack {
                gemDot(x: size * 0.24, y: size * 0.28)
                gemDot(x: size * 0.68, y: size * 0.38)
                gemDot(x: size * 0.44, y: size * 0.68)
            }
        case .weave:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.12)).frame(width: max(1, size * 0.10), height: size)
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size, height: max(1, size * 0.10))
            }
        case .hash:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.78, height: max(1, size * 0.08)).rotationEffect(.degrees(45))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.08)).frame(width: size * 0.70, height: max(1, size * 0.08)).rotationEffect(.degrees(-45))
            }
        case .mire:
            VStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.14)).frame(width: size * 0.90, height: max(1, size * 0.08))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.08)).frame(width: size * 0.58, height: max(1, size * 0.08))
                Rectangle().fill(Color.black.opacity(0.10)).frame(width: size * 0.30, height: max(1, size * 0.08))
            }
        case .circuit:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.74, height: max(1, size * 0.08))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: max(1, size * 0.08), height: size * 0.74)
                Rectangle().fill(Color.clear)
                    .frame(width: size * 0.54, height: size * 0.54)
                    .overlay(Rectangle().stroke(regionTheme.roomHighlight.opacity(0.10), lineWidth: max(1, size * 0.06)))
            }
        }
    }

    private func gemDot(x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(regionTheme.roomHighlight.opacity(0.12))
            .frame(width: max(1, x * 0.22), height: max(1, x * 0.22))
            .offset(x: x - (x * 0.11), y: y - (x * 0.11))
    }

    @ViewBuilder
    private func featureMark(size: CGFloat) -> some View {
        if visualTheme == .ultima {
            ultimaFeatureMark(size: size)
        } else {
            switch feature {
            case .none:
                EmptyView()
            case .chest:
                PixelSprite(color: palette.lightGold, pattern: [
                    [0,1,1,0],
                    [1,1,1,1],
                    [1,0,0,1]
                ])
                .frame(width: size * 0.62, height: size * 0.54)
            case .bed:
                Rectangle().fill(palette.text).frame(width: size * 0.66, height: size * 0.20)
            case .plateUp:
                Rectangle().fill(palette.accentViolet).frame(width: size * 0.58, height: size * 0.16)
            case .plateDown:
                Rectangle().fill(Color.black.opacity(0.28)).frame(width: size * 0.58, height: size * 0.16)
            case .switchIdle:
                PixelSprite(color: palette.accentBlue, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ])
                .frame(width: size * 0.48, height: size * 0.48)
            case .switchLit:
                PixelSprite(color: palette.lightGold, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ])
                .frame(width: size * 0.48, height: size * 0.48)
            case .shrine:
                PixelSprite(color: palette.accentViolet, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [1,0,1],
                    [0,1,0]
                ])
                .frame(width: size * 0.52, height: size * 0.62)
            case .beacon:
                PixelSprite(color: palette.lightGold, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [1,1,1],
                    [0,1,0]
                ])
                .frame(width: size * 0.56, height: size * 0.64)
            case .gate:
                Rectangle().fill(palette.titleGold).frame(width: size * 0.40, height: size * 0.74)
            }
        }
    }

    @ViewBuilder
    private func ultimaFeatureMark(size: CGFloat) -> some View {
        switch feature {
        case .none:
            EmptyView()
        case .chest:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.44, height: size * 0.28)
        case .bed:
            Rectangle().fill(palette.text).frame(width: size * 0.56, height: size * 0.14)
        case .plateUp:
            Rectangle().fill(palette.accentViolet).frame(width: size * 0.40, height: size * 0.12)
        case .plateDown:
            Rectangle().fill(Color.black.opacity(0.24)).frame(width: size * 0.40, height: size * 0.12)
        case .switchIdle:
            Rectangle().fill(palette.accentBlue).frame(width: size * 0.20, height: size * 0.20)
        case .switchLit:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.20, height: size * 0.20)
        case .shrine:
            Rectangle().fill(palette.accentViolet).frame(width: size * 0.26, height: size * 0.42)
        case .beacon:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.30, height: size * 0.46)
        case .gate:
            Rectangle().fill(palette.titleGold).frame(width: size * 0.24, height: size * 0.56)
        }
    }

    @ViewBuilder
    private func sprite(size: CGFloat) -> some View {
        if visualTheme == .ultima {
            switch occupant {
            case .none:
                EmptyView()
            case .player:
                simpleSprite(color: palette.text, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [1,0,1]
                ], size: size * 0.62)
            case .npc(let id):
                simpleSprite(color: npcColor(for: id), pattern: ultimaNPCPattern(for: id), size: size * 0.58)
            case .enemy(let id):
                simpleSprite(color: enemyColor(for: id), pattern: ultimaEnemyPattern(for: id), size: size * 0.64)
            case .boss:
                simpleSprite(color: palette.accentViolet, pattern: [
                    [1,1,1],
                    [1,0,1],
                    [1,1,1]
                ], size: size * 0.68)
            }
        } else {
            switch occupant {
            case .none:
                EmptyView()
            case .player:
                gemstoneSprite(
                    color: palette.text,
                    pattern: [
                        [0,1,1,0],
                        [1,1,1,1],
                        [1,0,0,1],
                        [1,0,0,1]
                    ],
                    size: size * 0.78
                )
            case .npc(let id):
                gemstoneSprite(color: npcColor(for: id), pattern: npcPattern(for: id), size: size * 0.76)
            case .enemy(let id):
                gemstoneSprite(color: enemyColor(for: id), pattern: enemyPattern(for: id), size: size * 0.84)
            case .boss:
                gemstoneSprite(
                    color: palette.accentViolet,
                    pattern: [
                        [1,0,1,0,1],
                        [1,1,1,1,1],
                        [0,1,1,1,0],
                        [1,0,1,0,1]
                    ],
                    size: size * 0.90
                )
            }
        }
    }

    private func simpleSprite(color: Color, pattern: [[Int]], size: CGFloat) -> some View {
        PixelSprite(color: color, pattern: pattern)
            .frame(width: size, height: size)
    }

    private func gemstoneSprite(color: Color, pattern: [[Int]], size: CGFloat) -> some View {
        ZStack {
            PixelSprite(color: Color.black.opacity(0.45), pattern: pattern)
                .offset(x: size * 0.06, y: size * 0.06)
            PixelSprite(color: color, pattern: pattern)
        }
        .frame(width: size, height: size)
    }

    private func npcPattern(for id: String) -> [[Int]] {
        switch id {
        case "elder":
            return [
                [0,1,1,0],
                [1,1,1,1],
                [1,0,1,1],
                [1,0,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1,0],
                [0,1,1,1],
                [0,1,0,1],
                [0,1,0,1]
            ]
        case "orchard_guide":
            return [
                [0,1,1,0],
                [1,1,0,1],
                [0,1,1,1],
                [1,0,1,0]
            ]
        default:
            return [
                [0,1,1,0],
                [1,1,1,1],
                [0,1,1,0],
                [1,0,1,0]
            ]
        }
    }

    private func ultimaNPCPattern(for id: String) -> [[Int]] {
        switch id {
        case "elder":
            return [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1],
                [0,1,0],
                [0,1,0]
            ]
        case "orchard_guide":
            return [
                [0,1,0],
                [1,1,0],
                [0,1,1]
            ]
        default:
            return [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        }
    }

    private func npcColor(for id: String) -> Color {
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

    private func enemyPattern(for id: String) -> [[Int]] {
        if id.hasPrefix("crow") {
            return [
                [1,0,0,1],
                [1,1,1,1],
                [0,1,1,0],
                [0,1,0,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,1,0,0],
                [1,1,1,1],
                [0,1,1,1],
                [1,0,0,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,1,0],
                [1,1,1,1],
                [1,1,1,1],
                [1,0,1,1]
            ]
        }
        return [
            [1,1,1,1],
            [1,0,0,1],
            [1,1,1,1],
            [0,1,1,0]
        ]
    }

    private func ultimaEnemyPattern(for id: String) -> [[Int]] {
        if id.hasPrefix("crow") {
            return [
                [1,0,1],
                [1,1,1],
                [0,1,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,0,0],
                [1,1,1],
                [0,0,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        }
        return [
            [1,1,1],
            [1,0,1],
            [1,1,1]
        ]
    }

    private func enemyColor(for id: String) -> Color {
        if id.hasPrefix("crow") {
            return palette.text
        }
        if id.hasPrefix("hound") {
            return palette.titleGold
        }
        if id.hasPrefix("wraith") {
            return palette.accentBlue
        }
        return palette.lightGold
    }
}
