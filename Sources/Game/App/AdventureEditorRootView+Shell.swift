#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension AdventureEditorRootView {
    var header: some View {
        AdventureEditorHeaderView(store: store, palette: palette)
    }

    var editorHeaderButtons: some View {
        AdventureEditorHeaderButtons(store: store, palette: palette)
    }

    var sourcePanel: some View {
        AdventureEditorSourcePanelView(store: store, palette: palette)
    }

    var validationPanel: some View {
        AdventureEditorValidationPanelView(store: store, palette: palette)
    }

    var metadataPanel: some View {
        AdventureEditorMetadataPanelView(store: store, palette: palette)
    }

    var mapListPanel: some View {
        EditorPanel(title: "MAPS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.maps.enumerated()), id: \.element.id) { index, map in
                            Button {
                                store.selectMap(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(map.name.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(map.id)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.document.selectedMapIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)

                HStack(spacing: 8) {
                    Button("ADD MAP") {
                        store.addMap()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DUP MAP") {
                        store.duplicateSelectedMap()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    var contentTabBar: some View {
        AdventureEditorContentTabBarView(store: store, palette: palette)
    }

    @ViewBuilder
    var contentPanel: some View {
        switch store.selectedContentTab {
        case .maps:
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    mapListPanel
                        .frame(width: 220)
                    mapEditorPanel
                }

                VStack(alignment: .leading, spacing: 12) {
                    mapListPanel
                    mapEditorPanel
                }
            }
        case .dialogues:
            dialoguesPanel
        case .questFlow:
            questFlowPanel
        case .encounters:
            encountersPanel
        case .shops:
            shopsPanel
        case .npcs:
            npcRosterPanel
        case .enemies:
            enemyRosterPanel
        }
    }

    var mapEditorPanel: some View {
        EditorPanel(title: "MAP WORKBENCH", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                if store.currentMap != nil {
                    HStack(spacing: 8) {
                        labeledField("MAP ID", text: Binding(
                            get: { store.currentMap?.id ?? "" },
                            set: { store.updateCurrentMapID($0) }
                        ))
                        labeledField("MAP NAME", text: Binding(
                            get: { store.currentMap?.name ?? "" },
                            set: { store.updateCurrentMapName($0) }
                        ))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEPTH BACKDROP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)

                        Picker(
                            "Depth Backdrop",
                            selection: Binding<DepthBackdropStyle?>(
                                get: { store.currentMap?.depthBackdrop },
                                set: { store.updateCurrentMapDepthBackdrop($0) }
                            )
                        ) {
                            Text("AUTO").tag(DepthBackdropStyle?.none)
                            Text("SKY").tag(DepthBackdropStyle?.some(.sky))
                            Text("CEILING").tag(DepthBackdropStyle?.some(.ceiling))
                        }
                        .pickerStyle(.segmented)

                        Text("AUTO FALLS BACK TO THE ENGINE HEURISTIC.")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text.opacity(0.72))
                    }

                    toolPalette

                    if store.selectedTool == .terrain {
                        tilePalette
                    }

                    if store.selectedTool == .interactable {
                        interactablePalette
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            mapCanvasPanel

                            selectionPanel
                                .frame(width: 210)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            mapCanvasPanel
                            selectionPanel
                        }
                    }
                } else {
                    Text("NO MAP IS ACTIVE.")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.text)
                }
            }
        }
    }

    var toolPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EDITOR TOOLS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            store.selectTool(tool)
                        } label: {
                            Text(tool.shortLabel)
                                .frame(minWidth: 44)
                        }
                        .buttonStyle(
                            EditorButtonStyle(
                                background: store.selectedTool == tool ? palette.title : palette.panelAlt
                            )
                        )
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            store.selectTool(tool)
                        } label: {
                            Text(tool.shortLabel)
                                .frame(minWidth: 58)
                        }
                        .buttonStyle(
                            EditorButtonStyle(
                                background: store.selectedTool == tool ? palette.title : palette.panelAlt
                            )
                        )
                    }
                }
            }
        }
    }

    var tilePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TILE PALETTE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(editorTilePalette, id: \.glyph) { tile in
                        Button {
                            store.selectedGlyph = tile.glyph
                        } label: {
                            tilePaletteSwatch(tile)
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(editorTilePalette, id: \.glyph) { tile in
                        Button {
                            store.selectedGlyph = tile.glyph
                        } label: {
                            tilePaletteSwatch(tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var interactablePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTERACTABLE KIND")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(editorInteractablePalette, id: \.kind) { choice in
                        Button {
                            store.selectedInteractableKind = choice.kind
                        } label: {
                            interactablePaletteSwatch(choice)
                        }
                        .buttonStyle(.plain)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(editorInteractablePalette, id: \.kind) { choice in
                        Button {
                            store.selectedInteractableKind = choice.kind
                        } label: {
                            interactablePaletteSwatch(choice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var selectionPanel: some View {
        EditorPanel(title: "SELECTION", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(store.selectionSummaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(palette.border)

                inspectorFields

                Divider()
                    .overlay(palette.border)

                Text("ACTIVE TOOL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Text(store.selectedTool.title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.title)

                Text(store.selectedTool.helpText.uppercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var dialoguesPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                dialogueListPanel
                    .frame(width: 240)
                dialogueEditorPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                dialogueListPanel
                dialogueEditorPanel
            }
        }
    }

    var questFlowPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                questStageListPanel
                    .frame(width: 240)
                questFlowEditorPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                questStageListPanel
                questFlowEditorPanel
            }
        }
    }

    var encountersPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                encounterListPanel
                    .frame(width: 240)
                encounterEditorPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                encounterListPanel
                encounterEditorPanel
            }
        }
    }

    var shopsPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                shopListPanel
                    .frame(width: 240)
                shopEditorPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                shopListPanel
                shopEditorPanel
            }
        }
    }

    var npcRosterPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                npcRosterListPanel
                    .frame(width: 250)
                selectionPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                npcRosterListPanel
                selectionPanel
            }
        }
    }

    var enemyRosterPanel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                enemyRosterListPanel
                    .frame(width: 250)
                selectionPanel
            }

            VStack(alignment: .leading, spacing: 12) {
                enemyRosterListPanel
                selectionPanel
            }
        }
    }

    var mapCanvasPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.currentMapCountsLine)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.84))

            Text(store.selectedToolSummary)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array((store.currentMap?.lines ?? []).enumerated()), id: \.offset) { y, line in
                        HStack(spacing: 1) {
                            ForEach(Array(line.enumerated()), id: \.offset) { x, glyph in
                                canvasCell(x: x, y: y, glyph: glyph)
                            }
                        }
                    }
                }
                .padding(6)
                .background(palette.panelAlt)
            }
            .frame(minHeight: 300)
            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
    }
}
#endif
