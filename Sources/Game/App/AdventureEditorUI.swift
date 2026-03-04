import AppKit
import Foundation
import SwiftUI

struct AdventureEditorRootView: View {
    @ObservedObject var store: AdventureEditorStore

    private let palette = AdventureEditorPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                VStack(spacing: 12) {
                    header

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            sourcePanel
                                .frame(width: 220)

                            VStack(spacing: 12) {
                                metadataPanel
                                contentTabBar
                                contentPanel
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            sourcePanel
                            metadataPanel
                            contentTabBar
                            contentPanel
                        }
                    }

                    footer
                }
                .padding(18)
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("CODEXITMA ADVENTURE EDITOR")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.title)
                Spacer()
                editorHeaderButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CODEXITMA ADVENTURE EDITOR")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.title)
                editorHeaderButtons
            }
        }
    }

    private var editorHeaderButtons: some View {
        HStack(spacing: 8) {
            Button("VALIDATE") {
                _ = store.validateCurrentPack()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

            Button("SAVE + PLAYTEST") {
                store.saveAndPlaytestCurrentPack()
            }
            .buttonStyle(EditorButtonStyle(background: palette.title))

            Button("SAVE PACK") {
                store.saveCurrentPack()
            }
            .buttonStyle(EditorButtonStyle(background: palette.action))
        }
    }

    private var sourcePanel: some View {
        EditorPanel(title: "SOURCES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SELECT A BUNDLED OR EXTERNAL ADVENTURE, THEN FORK IT INTO THE EDITOR.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.catalog, id: \.id) { entry in
                            Button {
                                store.selectCatalogAdventure(entry.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(entry.id.rawValue)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedCatalogID == entry.id ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)

                Button("NEW BLANK TEMPLATE") {
                    store.createBlankAdventure()
                }
                .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                validationPanel
            }
        }
    }

    private var validationPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VALIDATION")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            if store.validationMessages.isEmpty {
                Text("NO SAVED VALIDATION ISSUES. USE VALIDATE, SAVE, OR SAVE + PLAYTEST TO CHECK THE PACK.")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(store.validationMessages.prefix(5).enumerated()), id: \.offset) { _, issue in
                    Text("• \(issue.uppercased())")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if store.validationMessages.count > 5 {
                    Text("• ...AND \(store.validationMessages.count - 5) MORE")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.70))
                }
            }
        }
        .padding(.top, 6)
    }

    private var metadataPanel: some View {
        EditorPanel(title: "PACK METADATA", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    labeledField("FOLDER", text: Binding(
                        get: { store.document.folderName },
                        set: { store.updateFolderName($0) }
                    ))
                    labeledField("ADVENTURE ID", text: Binding(
                        get: { store.document.adventureID },
                        set: { store.updateAdventureID($0) }
                    ))
                }

                labeledField("TITLE", text: Binding(
                    get: { store.document.title },
                    set: { store.updateTitle($0) }
                ))

                labeledField("INTRO", text: Binding(
                    get: { store.document.introLine },
                    set: { store.updateIntroLine($0) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("SUMMARY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.document.summary },
                        set: { store.updateSummary($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(height: 72)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }

                Text("KEEP THE SAME ADVENTURE ID TO OVERRIDE A BUILT-IN PACK. CHANGE IT TO PUBLISH A NEW ADVENTURE.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(store.savePolicyLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var mapListPanel: some View {
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

    private var contentTabBar: some View {
        EditorPanel(title: "EDITOR DATA", palette: palette) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(EditorContentTab.allCases) { tab in
                        Button {
                            store.selectContentTab(tab)
                        } label: {
                            Text(tab.shortLabel)
                                .frame(minWidth: 64)
                        }
                        .buttonStyle(
                            EditorButtonStyle(
                                background: store.selectedContentTab == tab ? palette.title : palette.panelAlt
                            )
                        )
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(EditorContentTab.allCases) { tab in
                        Button {
                            store.selectContentTab(tab)
                        } label: {
                            Text(tab.shortLabel)
                                .frame(minWidth: 72)
                        }
                        .buttonStyle(
                            EditorButtonStyle(
                                background: store.selectedContentTab == tab ? palette.title : palette.panelAlt
                            )
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentPanel: some View {
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

    private var mapEditorPanel: some View {
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

    private var toolPalette: some View {
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

    private var tilePalette: some View {
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

    private var interactablePalette: some View {
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

    private var selectionPanel: some View {
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

    private var dialoguesPanel: some View {
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

    private var questFlowPanel: some View {
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

    private var encountersPanel: some View {
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

    private var shopsPanel: some View {
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

    private var npcRosterPanel: some View {
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

    private var enemyRosterPanel: some View {
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

    private var mapCanvasPanel: some View {
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

    private var dialogueListPanel: some View {
        EditorPanel(title: "DIALOGUES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.dialogues.enumerated()), id: \.element.id) { index, dialogue in
                            Button {
                                store.selectDialogue(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dialogue.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(dialogue.speaker)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedDialogueIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addDialogue()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedDialogue()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    private var dialogueEditorPanel: some View {
        EditorPanel(title: "DIALOGUE EDITOR", palette: palette) {
            if let dialogue = store.selectedDialogue {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("DIALOGUE ID", text: Binding(
                        get: { store.selectedDialogue?.id ?? dialogue.id },
                        set: { store.updateSelectedDialogueID($0) }
                    ))

                    labeledField("SPEAKER", text: Binding(
                        get: { store.selectedDialogue?.speaker ?? dialogue.speaker },
                        set: { store.updateSelectedDialogueSpeaker($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("LINES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { (store.selectedDialogue?.lines ?? dialogue.lines).joined(separator: "\n") },
                            set: { store.updateSelectedDialogueLinesText($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(minHeight: 180)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                }
            } else {
                emptyEditorLabel("NO DIALOGUE IS AVAILABLE.")
            }
        }
    }

    private var questStageListPanel: some View {
        EditorPanel(title: "QUEST STAGES", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.questFlow.stages.enumerated()), id: \.offset) { index, stage in
                            Button {
                                store.selectQuestStage(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("STAGE \(index + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(stage.objective)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .lineLimit(2)
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedQuestStageIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addQuestStage()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedQuestStage()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    private var questFlowEditorPanel: some View {
        EditorPanel(title: "QUEST FLOW", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                if let stage = store.selectedQuestStage {
                    labeledField("OBJECTIVE", text: Binding(
                        get: { store.selectedQuestStage?.objective ?? stage.objective },
                        set: { store.updateSelectedQuestObjective($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMPLETE WHEN FLAG")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)

                        Picker("Quest Flag", selection: Binding(
                            get: { store.selectedQuestStage?.completeWhenFlag ?? stage.completeWhenFlag },
                            set: { store.updateSelectedQuestFlag($0) }
                        )) {
                            ForEach(QuestFlag.allCases, id: \.self) { flag in
                                Text(flag.rawValue).tag(flag)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("COMPLETION TEXT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.document.questFlow.completionText },
                        set: { store.updateQuestCompletionText($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(minHeight: 140)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }
            }
        }
    }

    private var encounterListPanel: some View {
        EditorPanel(title: "ENCOUNTERS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.encounters.enumerated()), id: \.element.id) { index, encounter in
                            Button {
                                store.selectEncounter(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(encounter.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(encounter.enemyID)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedEncounterIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addEncounter()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedEncounter()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    private var encounterEditorPanel: some View {
        EditorPanel(title: "ENCOUNTER EDITOR", palette: palette) {
            if let encounter = store.selectedEncounter {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("ENCOUNTER ID", text: Binding(
                        get: { store.selectedEncounter?.id ?? encounter.id },
                        set: { store.updateSelectedEncounterID($0) }
                    ))

                    labeledField("ENEMY ID", text: Binding(
                        get: { store.selectedEncounter?.enemyID ?? encounter.enemyID },
                        set: { store.updateSelectedEncounterEnemyID($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INTRO LINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { store.selectedEncounter?.introLine ?? encounter.introLine },
                            set: { store.updateSelectedEncounterIntro($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(minHeight: 140)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                }
            } else {
                emptyEditorLabel("NO ENCOUNTER IS AVAILABLE.")
            }
        }
    }

    private var shopListPanel: some View {
        EditorPanel(title: "SHOPS", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.document.shops.enumerated()), id: \.element.id) { index, shop in
                            Button {
                                store.selectShop(index: index)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shop.id.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(shop.merchantName)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .opacity(0.78)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(store.selectedShopIndex == index ? palette.selection : palette.panelAlt)
                                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)

                HStack(spacing: 8) {
                    Button("ADD") {
                        store.addShop()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                    Button("DROP") {
                        store.removeSelectedShop()
                    }
                    .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                }
            }
        }
    }

    private var shopEditorPanel: some View {
        EditorPanel(title: "SHOP EDITOR", palette: palette) {
            if let shop = store.selectedShop {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("SHOP ID", text: Binding(
                        get: { store.selectedShop?.id ?? shop.id },
                        set: { store.updateSelectedShopID($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MERCHANT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        Picker("Merchant", selection: Binding(
                            get: { store.selectedShop?.merchantID ?? shop.merchantID },
                            set: { store.updateSelectedShopMerchantID($0) }
                        )) {
                            ForEach(store.document.npcs, id: \.id) { npc in
                                Text(npc.name.uppercased()).tag(npc.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("INTRO LINE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.label)
                        TextEditor(text: Binding(
                            get: { store.selectedShop?.introLine ?? shop.introLine },
                            set: { store.updateSelectedShopIntro($0) }
                        ))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(palette.text)
                        .frame(height: 72)
                        .padding(6)
                        .background(palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }

                    Text("OFFERS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            shopOfferListPanel
                                .frame(width: 200)
                            shopOfferDetailsPanel
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            shopOfferListPanel
                            shopOfferDetailsPanel
                        }
                    }

                    HStack(spacing: 8) {
                        Button("ADD OFFER") {
                            store.addShopOffer()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

                        Button("DROP OFFER") {
                            store.removeSelectedShopOffer()
                        }
                        .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
                    }
                }
            } else {
                emptyEditorLabel("NO SHOP IS AVAILABLE.")
            }
        }
    }

    private var shopOfferListPanel: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array((store.selectedShop?.offers ?? []).enumerated()), id: \.element.id) { index, offer in
                    Button {
                        store.selectShopOffer(index: index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offer.id.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text("\(offer.itemID.rawValue)  \(offer.price)M")
                                .font(.system(size: 8, weight: .regular, design: .monospaced))
                                .opacity(0.78)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(store.selectedShopOfferIndex == index ? palette.selection : palette.panelAlt)
                        .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private var shopOfferDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let offer = store.selectedShopOffer {
                labeledField("OFFER ID", text: Binding(
                    get: { store.selectedShopOffer?.id ?? offer.id },
                    set: { store.updateSelectedShopOfferID($0) }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("ITEM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    Picker("Item", selection: Binding(
                        get: { store.selectedShopOffer?.itemID ?? offer.itemID },
                        set: { store.updateSelectedShopOfferItemID($0) }
                    )) {
                        ForEach(ItemID.allCases, id: \.self) { itemID in
                            Text(itemID.rawValue).tag(itemID)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                labeledStepper("PRICE", value: Binding(
                    get: { store.selectedShopOffer?.price ?? offer.price },
                    set: { store.updateSelectedShopOfferPrice($0) }
                ), range: 0...99)

                VStack(alignment: .leading, spacing: 4) {
                    Text("BLURB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                    TextEditor(text: Binding(
                        get: { store.selectedShopOffer?.blurb ?? offer.blurb },
                        set: { store.updateSelectedShopOfferBlurb($0) }
                    ))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.text)
                    .frame(height: 64)
                    .padding(6)
                    .background(palette.panelAlt)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                }

                Toggle(isOn: Binding(
                    get: { store.selectedShopOffer?.repeatable ?? offer.repeatable },
                    set: { store.updateSelectedShopOfferRepeatable($0) }
                )) {
                    Text("REPEATABLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.label)
                }
                .toggleStyle(.checkbox)
            } else {
                emptyEditorLabel("NO OFFER IS SELECTED.")
            }
        }
    }

    private var npcRosterListPanel: some View {
        EditorPanel(title: "NPC ROSTER", palette: palette) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.document.npcs, id: \.id) { npc in
                        Button {
                            store.focusNPC(id: npc.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(npc.name.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("\(npc.id)  @ \(npc.mapID)")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .opacity(0.78)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(store.selectedNPC?.id == npc.id ? palette.selection : palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var enemyRosterListPanel: some View {
        EditorPanel(title: "ENEMY ROSTER", palette: palette) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.document.enemies, id: \.id) { enemy in
                        Button {
                            store.focusEnemy(id: enemy.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(enemy.name.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text("\(enemy.id)  @ \(enemy.mapID)")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .opacity(0.78)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(store.selectedEnemy?.id == enemy.id ? palette.selection : palette.panelAlt)
                            .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    @ViewBuilder
    private var inspectorFields: some View {
        if let npc = store.selectedNPC {
            Text("NPC INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("NPC ID", text: Binding(
                get: { store.selectedNPC?.id ?? npc.id },
                set: { store.updateSelectedNPCID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedNPC?.name ?? npc.name },
                set: { store.updateSelectedNPCName($0) }
            ))

            labeledField("DIALOGUE", text: Binding(
                get: { store.selectedNPC?.dialogueID ?? npc.dialogueID },
                set: { store.updateSelectedNPCDialogueID($0) }
            ))

            Text("SHOP \(store.selectedNPCShop?.id.uppercased() ?? "NONE")")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.82))

            Button(store.selectedNPCShop == nil ? "CREATE SHOP" : "OPEN SHOP") {
                store.ensureShopForSelectedNPC()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))
        } else if let enemy = store.selectedEnemy {
            Text("ENEMY INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("ENEMY ID", text: Binding(
                get: { store.selectedEnemy?.id ?? enemy.id },
                set: { store.updateSelectedEnemyID($0) }
            ))

            labeledField("NAME", text: Binding(
                get: { store.selectedEnemy?.name ?? enemy.name },
                set: { store.updateSelectedEnemyName($0) }
            ))

            HStack(spacing: 8) {
                labeledStepper("HP", value: Binding(
                    get: { store.selectedEnemy?.hp ?? enemy.hp },
                    set: { store.updateSelectedEnemyHP($0) }
                ), range: 1...99)

                labeledStepper("ATK", value: Binding(
                    get: { store.selectedEnemy?.attack ?? enemy.attack },
                    set: { store.updateSelectedEnemyAttack($0) }
                ), range: 0...25)

                labeledStepper("DEF", value: Binding(
                    get: { store.selectedEnemy?.defense ?? enemy.defense },
                    set: { store.updateSelectedEnemyDefense($0) }
                ), range: 0...25)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AI")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("AI", selection: Binding(
                    get: { store.selectedEnemy?.ai ?? enemy.ai },
                    set: { store.updateSelectedEnemyAI($0) }
                )) {
                    ForEach([AIKind.idle, .stalk, .guardian, .boss], id: \.self) { ai in
                        Text(ai.rawValue).tag(ai)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let interactable = store.selectedInteractable {
            Text("INTERACTABLE INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            labeledField("OBJECT ID", text: Binding(
                get: { store.selectedInteractable?.id ?? interactable.id },
                set: { store.updateSelectedInteractableID($0) }
            ))

            labeledField("TITLE", text: Binding(
                get: { store.selectedInteractable?.title ?? interactable.title },
                set: { store.updateSelectedInteractableTitle($0) }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Text("KIND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Kind", selection: Binding(
                    get: { store.selectedInteractable?.kind ?? interactable.kind },
                    set: { store.updateSelectedInteractableKind($0) }
                )) {
                    ForEach(editorInteractablePalette, id: \.kind) { choice in
                        Text(choice.label).tag(choice.kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("REWARD ITEM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Reward Item", selection: Binding(
                    get: { store.selectedInteractable?.rewardItem ?? interactable.rewardItem },
                    set: { store.updateSelectedInteractableRewardItem($0) }
                )) {
                    Text("NONE").tag(Optional<ItemID>.none)
                    ForEach(ItemID.allCases, id: \.self) { itemID in
                        Text(itemID.rawValue).tag(Optional(itemID))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            labeledStepper("REWARD MARKS", value: Binding(
                get: { store.selectedInteractable?.rewardMarks ?? interactable.rewardMarks ?? 0 },
                set: { store.updateSelectedInteractableRewardMarks($0) }
            ), range: 0...999)

            VStack(alignment: .leading, spacing: 4) {
                Text("REQUIRED FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Required Flag", selection: Binding(
                    get: { store.selectedInteractable?.requiredFlag ?? interactable.requiredFlag },
                    set: { store.updateSelectedInteractableRequiredFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GRANTS FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Grants Flag", selection: Binding(
                    get: { store.selectedInteractable?.grantsFlag ?? interactable.grantsFlag },
                    set: { store.updateSelectedInteractableGrantsFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        } else if let portal = store.selectedPortal {
            Text("PORTAL INSPECTOR")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            VStack(alignment: .leading, spacing: 4) {
                Text("DESTINATION MAP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Destination Map", selection: Binding(
                    get: { store.selectedPortal?.toMap ?? portal.toMap },
                    set: { store.updateSelectedPortalDestinationMap($0) }
                )) {
                    ForEach(store.document.maps, id: \.id) { map in
                        Text(map.name.uppercased()).tag(map.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Button("SYNC TO MAP SPAWN") {
                store.syncSelectedPortalToDestinationSpawn()
            }
            .buttonStyle(EditorButtonStyle(background: palette.panelAlt))

            VStack(alignment: .leading, spacing: 4) {
                Text("REQUIRED FLAG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)

                Picker("Portal Flag", selection: Binding(
                    get: { store.selectedPortal?.requiredFlag ?? portal.requiredFlag },
                    set: { store.updateSelectedPortalRequiredFlag($0) }
                )) {
                    Text("NONE").tag(Optional<QuestFlag>.none)
                    ForEach(QuestFlag.allCases, id: \.self) { flag in
                        Text(flag.rawValue).tag(Optional(flag))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("BLOCKED TEXT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.label)
                TextEditor(text: Binding(
                    get: { store.selectedPortal?.blockedMessage ?? portal.blockedMessage ?? "" },
                    set: { store.updateSelectedPortalBlockedMessage($0) }
                ))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .scrollContentBackground(.hidden)
                .foregroundStyle(palette.text)
                .frame(height: 72)
                .padding(6)
                .background(palette.panelAlt)
                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
            }

            HStack(spacing: 8) {
                labeledStepper("TO X", value: Binding(
                    get: { store.selectedPortal?.toPosition.x ?? portal.toPosition.x },
                    set: { store.updateSelectedPortalDestinationX($0) }
                ), range: 0...99)

                labeledStepper("TO Y", value: Binding(
                    get: { store.selectedPortal?.toPosition.y ?? portal.toPosition.y },
                    set: { store.updateSelectedPortalDestinationY($0) }
                ), range: 0...99)
            }
        } else {
            Text("NO EDITABLE OBJECT IS SELECTED.")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.80))
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(store.statusLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .lineLimit(2)
                Spacer()
                Text("EXPORTS TO ~/LIBRARY/APPLICATION SUPPORT/CODEXITMA/ADVENTURES")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.statusLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .lineLimit(3)
                Text("EXPORTS TO ~/LIBRARY/APPLICATION SUPPORT/CODEXITMA/ADVENTURES")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.72))
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
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

    private func emptyEditorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.80))
    }

    private func labeledStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
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

    private func canvasCell(x: Int, y: Int, glyph: Character) -> some View {
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

    private func tilePaletteSwatch(_ tile: EditorTileChoice) -> some View {
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

    private func interactablePaletteSwatch(_ choice: EditorInteractableChoice) -> some View {
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

    private func tileColor(for glyph: Character) -> Color {
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

    private func displayGlyph(_ glyph: Character) -> String {
        glyph == " " ? "·" : String(glyph)
    }
}
