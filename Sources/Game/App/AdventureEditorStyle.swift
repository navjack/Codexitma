import AppKit
import Foundation
import SwiftUI

struct AdventureEditorPalette {
    let background = Color.black
    let panel = Color(red: 0.03, green: 0.03, blue: 0.02)
    let panelAlt = Color(red: 0.08, green: 0.08, blue: 0.06)
    let text = Color(red: 0.95, green: 0.94, blue: 0.87)
    let label = Color(red: 0.98, green: 0.79, blue: 0.24)
    let title = Color(red: 0.98, green: 0.86, blue: 0.28)
    let border = Color(red: 0.36, green: 0.28, blue: 0.12)
    let selection = Color(red: 0.21, green: 0.18, blue: 0.08)
    let action = Color(red: 0.68, green: 0.40, blue: 0.08)
    let ground = Color(red: 0.36, green: 0.24, blue: 0.09)
    let wall = Color(red: 0.42, green: 0.42, blue: 0.46)
    let water = Color(red: 0.14, green: 0.56, blue: 0.86)
    let brush = Color(red: 0.23, green: 0.74, blue: 0.18)
    let door = Color(red: 0.82, green: 0.62, blue: 0.14)
    let light = Color(red: 0.98, green: 0.90, blue: 0.38)
    let shrine = Color(red: 0.70, green: 0.30, blue: 0.84)
    let beacon = Color(red: 0.99, green: 0.92, blue: 0.34)
}

struct EditorPanel<Content: View>: View {
    let title: String
    let palette: AdventureEditorPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.title)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
        .overlay(Rectangle().stroke(palette.border, lineWidth: 2))
    }
}

struct EditorButtonStyle: ButtonStyle {
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? background.opacity(0.75) : background)
            .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.78, blue: 0.18), lineWidth: 1))
    }
}

struct EditorTileChoice {
    let glyph: Character
    let label: String
}

struct EditorInteractableChoice {
    let kind: InteractableKind
    let glyph: String
    let label: String
    let color: Color
}

let editorTilePalette: [EditorTileChoice] = [
    EditorTileChoice(glyph: ".", label: "FLR"),
    EditorTileChoice(glyph: "#", label: "WAL"),
    EditorTileChoice(glyph: "~", label: "WTR"),
    EditorTileChoice(glyph: "\"", label: "BRS"),
    EditorTileChoice(glyph: "+", label: "LCK"),
    EditorTileChoice(glyph: "/", label: "OPN"),
    EditorTileChoice(glyph: "*", label: "SHR"),
    EditorTileChoice(glyph: ">", label: "STA"),
    EditorTileChoice(glyph: "B", label: "BCN"),
    EditorTileChoice(glyph: " ", label: "EMP"),
]

let editorInteractablePalette: [EditorInteractableChoice] = [
    EditorInteractableChoice(
        kind: .chest,
        glyph: "$",
        label: "CHEST",
        color: Color(red: 0.84, green: 0.56, blue: 0.12)
    ),
    EditorInteractableChoice(
        kind: .shrine,
        glyph: "*",
        label: "SHRINE",
        color: Color(red: 0.78, green: 0.42, blue: 0.94)
    ),
    EditorInteractableChoice(
        kind: .bed,
        glyph: "Z",
        label: "BED",
        color: Color(red: 0.65, green: 0.32, blue: 0.18)
    ),
    EditorInteractableChoice(
        kind: .gate,
        glyph: "+",
        label: "GATE",
        color: Color(red: 0.88, green: 0.72, blue: 0.18)
    ),
    EditorInteractableChoice(
        kind: .beacon,
        glyph: "B",
        label: "BEACON",
        color: Color(red: 0.99, green: 0.94, blue: 0.34)
    ),
    EditorInteractableChoice(
        kind: .plate,
        glyph: "o",
        label: "PLATE",
        color: Color(red: 0.72, green: 0.72, blue: 0.72)
    ),
    EditorInteractableChoice(
        kind: .switchRune,
        glyph: "=",
        label: "RUNE",
        color: Color(red: 0.28, green: 0.74, blue: 0.90)
    ),
]
