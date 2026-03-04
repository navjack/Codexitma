#if canImport(AppKit)
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
                        .fill(overlayFillColor(for: overlay.style))
                        .padding(2)
                    Text(overlay.glyph)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(overlayTextColor(for: overlay.style))
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

    func overlayFillColor(for style: EditorCanvasOverlayStyle) -> Color {
        switch style {
        case .ansi(let ansi):
            return color(for: ansi)
        case .interactable(let kind):
            return color(for: kind)
        case .portal:
            return Color(red: 0.98, green: 0.82, blue: 0.20)
        case .spawn:
            return Color(red: 0.98, green: 0.95, blue: 0.62)
        }
    }

    func overlayTextColor(for style: EditorCanvasOverlayStyle) -> Color {
        switch style {
        case .ansi(.black), .ansi(.blue), .ansi(.magenta), .ansi(.brightBlack):
            return palette.text
        case .ansi, .interactable, .portal, .spawn:
            return .black
        }
    }

    func color(for ansi: ANSIColor) -> Color {
        switch ansi {
        case .black:
            return .black
        case .red:
            return Color(red: 0.86, green: 0.22, blue: 0.16)
        case .green:
            return Color(red: 0.27, green: 0.78, blue: 0.19)
        case .yellow:
            return Color(red: 0.98, green: 0.84, blue: 0.20)
        case .blue:
            return Color(red: 0.24, green: 0.56, blue: 0.92)
        case .magenta:
            return Color(red: 0.76, green: 0.34, blue: 0.86)
        case .cyan:
            return Color(red: 0.22, green: 0.80, blue: 0.86)
        case .white:
            return Color(red: 0.95, green: 0.94, blue: 0.87)
        case .brightBlack:
            return Color(red: 0.42, green: 0.42, blue: 0.44)
        case .reset:
            return Color(red: 0.95, green: 0.94, blue: 0.87)
        }
    }

    func color(for kind: InteractableKind) -> Color {
        switch kind {
        case .npc:
            return Color(red: 0.98, green: 0.84, blue: 0.20)
        case .shrine:
            return Color(red: 0.78, green: 0.42, blue: 0.94)
        case .chest:
            return Color(red: 0.84, green: 0.56, blue: 0.12)
        case .bed:
            return Color(red: 0.65, green: 0.32, blue: 0.18)
        case .gate:
            return Color(red: 0.88, green: 0.72, blue: 0.18)
        case .beacon:
            return Color(red: 0.99, green: 0.94, blue: 0.34)
        case .plate:
            return Color(red: 0.72, green: 0.72, blue: 0.72)
        case .switchRune:
            return Color(red: 0.28, green: 0.74, blue: 0.90)
        }
    }
}
#endif
