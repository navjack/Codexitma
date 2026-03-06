#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

struct MapBoardView: View {
    let state: GameState
    let scene: GraphicsSceneSnapshot
    let palette: UltimaPalette
    let visualTheme: GraphicsVisualTheme
    let showLightingDebug: Bool

    private let cell: CGFloat = 14
    static let depthTextureAtlas = DepthTextureAtlas.load()
    nonisolated(unsafe) static var depthFloorProjectionCache: [DepthFloorProjectionKey: [DepthFloorBandProjection]] = [:]

    var body: some View {
        if visualTheme == .depth3D {
            firstPersonView(theme: regionTheme)
        } else {
            topDownView(board: scene.board, theme: regionTheme)
        }
    }

    private func topDownView(board: MapBoardSnapshot, theme: RegionTheme) -> some View {
        let boardPadding = visualTheme == .gemstone ? 4.0 : 2.0
        let boardScale = visualTheme == .gemstone ? 2.0 : 1.84
        let boardWidth = CGFloat(board.width) * cell
        let boardHeight = CGFloat(board.height) * cell
        let lighting = scene.mapLighting
        let boardContent = AnyView(
            ZStack {
                VStack(spacing: 0) {
                    ForEach(Array(board.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.position) { cellSnapshot in
                                tileView(for: cellSnapshot, theme: theme)
                            }
                        }
                    }
                }
                if let lighting {
                    topDownLightingOverlay(board: board, lighting: lighting, theme: theme)
                }
            }
        )

        return ZStack(alignment: .topLeading) {
            if visualTheme == .gemstone {
                Rectangle()
                    .fill(theme.roomShadow)
                    .offset(x: 3, y: 3)
            }

            boardContent
                .padding(boardPadding)
                .background(visualTheme == .gemstone ? Color.black : theme.floor.opacity(0.22))
                .overlay(
                    Rectangle()
                        .stroke(
                            visualTheme == .gemstone ? theme.roomHighlight : palette.lightGold.opacity(0.75),
                            lineWidth: visualTheme == .gemstone ? 2 : 1
                        )
                        .padding(visualTheme == .gemstone ? 3 : 0)
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            visualTheme == .gemstone ? theme.roomBorder : palette.lightGold,
                            lineWidth: visualTheme == .gemstone ? 4 : 2
                        )
                )
        }
        .scaleEffect(boardScale, anchor: .topLeading)
        .frame(
            width: (boardWidth + (boardPadding * 2)) * boardScale,
            height: (boardHeight + (boardPadding * 2)) * boardScale,
            alignment: .topLeading
        )
        .clipped()
        .drawingGroup(opaque: false)
    }

    private func tileView(for cellSnapshot: BoardCellSnapshot, theme: RegionTheme) -> some View {
        let tileColor = cellSnapshot.tile
        let occupant = cellSnapshot.occupant
        let feature = cellSnapshot.feature

        return LowResTileView(
            tile: tileColor,
            occupant: occupant,
            feature: feature,
            palette: palette,
            regionTheme: theme,
            visualTheme: visualTheme
        )
        .frame(width: cell, height: cell)
    }

    private func topDownLightingOverlay(
        board: MapBoardSnapshot,
        lighting: DepthTileLightingSnapshot,
        theme: RegionTheme
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(board.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.position) { cellSnapshot in
                        let light = lighting.level(at: cellSnapshot.position)
                        let lift = max(0.0, light - lighting.ambient)
                        let dim = max(0.0, lighting.ambient - light)
                        ZStack {
                            if lift > 0.01 {
                                Rectangle()
                                    .fill(theme.roomHighlight.opacity(min(0.54, 0.10 + (lift * 0.85))))
                            }
                            if dim > 0.01 {
                                Rectangle()
                                    .fill(Color.black.opacity(min(0.54, 0.08 + (dim * 0.92))))
                            }
                        }
                        .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

}
#endif
