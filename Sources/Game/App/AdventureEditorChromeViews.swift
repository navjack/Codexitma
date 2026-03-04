#if canImport(AppKit)
import Foundation
import SwiftUI

@MainActor
struct AdventureEditorHeaderView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                titleLabel(compact: false)
                Spacer()
                AdventureEditorHeaderButtons(store: store, palette: palette)
            }

            VStack(alignment: .leading, spacing: 8) {
                titleLabel(compact: true)
                AdventureEditorHeaderButtons(store: store, palette: palette)
            }
        }
    }

    @ViewBuilder
    private func titleLabel(compact: Bool) -> some View {
        Text("CODEXITMA ADVENTURE EDITOR")
            .font(.system(size: compact ? 18 : 20, weight: .bold, design: .monospaced))
            .foregroundStyle(palette.title)
    }
}

@MainActor
struct AdventureEditorHeaderButtons: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
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
}

@MainActor
struct AdventureEditorSourcePanelView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
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

                AdventureEditorValidationPanelView(store: store, palette: palette)
            }
        }
    }
}

@MainActor
struct AdventureEditorValidationPanelView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
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
}

@MainActor
struct AdventureEditorMetadataPanelView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
        EditorPanel(title: "PACK METADATA", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    EditorLabeledField(
                        label: "FOLDER",
                        text: Binding(
                            get: { store.document.folderName },
                            set: { store.updateFolderName($0) }
                        ),
                        palette: palette
                    )
                    EditorLabeledField(
                        label: "ADVENTURE ID",
                        text: Binding(
                            get: { store.document.adventureID },
                            set: { store.updateAdventureID($0) }
                        ),
                        palette: palette
                    )
                }

                EditorLabeledField(
                    label: "TITLE",
                    text: Binding(
                        get: { store.document.title },
                        set: { store.updateTitle($0) }
                    ),
                    palette: palette
                )

                EditorLabeledField(
                    label: "INTRO",
                    text: Binding(
                        get: { store.document.introLine },
                        set: { store.updateIntroLine($0) }
                    ),
                    palette: palette
                )

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
}

@MainActor
struct AdventureEditorContentTabBarView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
        EditorPanel(title: "EDITOR DATA", palette: palette) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(EditorContentTab.allCases) { tab in
                        tabButton(for: tab, minWidth: 64)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(EditorContentTab.allCases) { tab in
                        tabButton(for: tab, minWidth: 72)
                    }
                }
            }
        }
    }

    private func tabButton(for tab: EditorContentTab, minWidth: CGFloat) -> some View {
        Button {
            store.selectContentTab(tab)
        } label: {
            Text(tab.shortLabel)
                .frame(minWidth: minWidth)
        }
        .buttonStyle(
            EditorButtonStyle(
                background: store.selectedContentTab == tab ? palette.title : palette.panelAlt
            )
        )
    }
}

@MainActor
struct AdventureEditorFooterView: View {
    @ObservedObject var store: AdventureEditorStore
    let palette: AdventureEditorPalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(store.statusLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .lineLimit(2)
                Spacer()
                footerLabel
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.statusLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.84))
                    .lineLimit(3)
                footerLabel
            }
        }
    }

    private var footerLabel: some View {
        Text("EXPORTS TO ~/LIBRARY/APPLICATION SUPPORT/CODEXITMA/ADVENTURES")
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.72))
    }
}

@MainActor
private struct EditorLabeledField: View {
    let label: String
    @Binding var text: String
    let palette: AdventureEditorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .padding(6)
                .background(palette.panelAlt)
                .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
