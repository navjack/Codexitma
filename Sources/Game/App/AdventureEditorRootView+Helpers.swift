import AppKit
import Foundation
import SwiftUI

extension AdventureEditorRootView {
    var footer: some View {
        AdventureEditorFooterView(store: store, palette: palette)
    }

    func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .padding(6)
                .background(palette.panelAlt)
                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func emptyEditorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.80))
    }

    func labeledStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                Stepper("", value: value, in: range)
                    .labelsHidden()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .background(palette.panelAlt)
            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func canvasCell(x: Int, y: Int, glyph: Character) -> some View {
        let overlay = store.overlay(atX: x, y: y)
        let isSpawn = store.isSpawn(x: x, y: y)
        let isSelected = store.isSelected(x: x, y: y)

        return Button {
            store.handleCanvasClick(x: x, y: y)
        } label: {
            ZStack {
                Rectangle()
                    .fill(tileColor(for: glyph))

                if isSpawn {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(palette.light.opacity(0.85), lineWidth: 1.2)
                        .padding(2)
                }

                if let overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(overlay.fill)
                        .padding(2)
                    Text(overlay.glyph)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(overlay.text)
                } else {
                    Text(displayGlyph(glyph))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.background)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(
                Rectangle().stroke(
                    isSelected ? palette.title : palette.border.opacity(0.55),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    func tilePaletteSwatch(_ tile: EditorTileChoice) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Rectangle()
                    .fill(tileColor(for: tile.glyph))
                Text(displayGlyph(tile.glyph))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.background)
            }
            .frame(width: 26, height: 26)
            .overlay(
                Rectangle().stroke(
                    store.selectedGlyph == tile.glyph ? palette.title : palette.border,
                    lineWidth: store.selectedGlyph == tile.glyph ? 2 : 1
                )
            )
            Text(tile.label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.82))
        }
    }

    func interactablePaletteSwatch(_ choice: EditorInteractableChoice) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Rectangle()
                    .fill(choice.color)
                Text(choice.glyph)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 26, height: 26)
            .overlay(
                Rectangle().stroke(
                    store.selectedInteractableKind == choice.kind ? palette.title : palette.border,
                    lineWidth: store.selectedInteractableKind == choice.kind ? 2 : 1
                )
            )
            Text(choice.label)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.82))
        }
    }

    func tileColor(for glyph: Character) -> Color {
        switch TileFactory.tile(for: glyph).type {
        case .floor:
            return palette.ground
        case .wall:
            return palette.wall
        case .water:
            return palette.water
        case .brush:
            return palette.brush
        case .doorLocked:
            return palette.door
        case .doorOpen:
            return palette.light
        case .shrine:
            return palette.shrine
        case .stairs:
            return palette.light
        case .beacon:
            return palette.beacon
        }
    }

    func displayGlyph(_ glyph: Character) -> String {
        glyph == " " ? "·" : String(glyph)
    }
}
