import AppKit
import Foundation
import SwiftUI

@MainActor
enum AdventureEditorLauncher {
    private static var retainedDelegate: AdventureEditorAppDelegate?

    static func run(library: GameContentLibrary) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AdventureEditorAppDelegate(library: library)
        retainedDelegate = delegate
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

@MainActor
final class AdventureEditorAppDelegate: NSObject, NSApplicationDelegate {
    private let store: AdventureEditorStore
    private var window: NSWindow?

    init(library: GameContentLibrary) {
        self.store = AdventureEditorStore(library: library)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma Adventure Editor"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 1180, height: 760)
        window.center()
        window.contentView = NSHostingView(rootView: AdventureEditorRootView(store: store))
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class AdventureEditorStore: ObservableObject {
    @Published var selectedCatalogID: AdventureID?
    @Published var document: EditableAdventureDocument
    @Published var selectedGlyph: Character = "#"
    @Published var statusLine = "READY. FORK AN ADVENTURE OR CREATE A NEW TEMPLATE."

    let catalog: [AdventureCatalogEntry]

    private let library: GameContentLibrary
    private let exporter: AdventurePackExporter

    init(
        library: GameContentLibrary,
        exporter: AdventurePackExporter = AdventurePackExporter()
    ) {
        self.library = library
        self.catalog = library.catalog
        self.exporter = exporter

        if let first = library.catalog.first {
            self.selectedCatalogID = first.id
            self.document = Self.makeDocument(
                entry: first,
                content: library.content(for: first.id)
            )
            self.statusLine = "READY. \(first.title.uppercased()) IS LOADED INTO THE EDITOR."
        } else {
            self.document = Self.makeBlankDocument()
        }
    }

    var currentMap: EditableMap? {
        guard !document.maps.isEmpty else { return nil }
        let index = max(0, min(document.selectedMapIndex, document.maps.count - 1))
        return document.maps[index]
    }

    func selectCatalogAdventure(_ adventureID: AdventureID) {
        selectedCatalogID = adventureID
        let entry = library.entry(for: adventureID) ?? AdventureCatalogEntry(
            id: adventureID,
            folder: adventureID.rawValue,
            packFile: "adventure.json",
            title: adventureID.rawValue,
            summary: "",
            introLine: ""
        )
        document = Self.makeDocument(entry: entry, content: library.content(for: adventureID))
        statusLine = "LOADED \(entry.title.uppercased()) FOR EDITING."
    }

    func createBlankAdventure() {
        selectedCatalogID = nil
        document = Self.makeBlankDocument()
        statusLine = "BLANK TEMPLATE CREATED. SAVE IT TO EXPORT A NEW ADVENTURE PACK."
    }

    func saveCurrentPack() {
        do {
            let exportedURL = try exporter.save(document: document)
            statusLine = "EXPORTED TO \(exportedURL.path.uppercased())"
        } catch {
            statusLine = "EXPORT FAILED: \(String(describing: error).uppercased())"
        }
    }

    func selectMap(index: Int) {
        guard !document.maps.isEmpty else { return }
        document.selectedMapIndex = max(0, min(index, document.maps.count - 1))
    }

    func addMap() {
        let nextIndex = document.maps.count + 1
        let newMap = EditableMap(
            id: "new_map_\(nextIndex)",
            name: "New Map \(nextIndex)",
            lines: Self.makeStarterMapLines(),
            spawn: Position(x: 2, y: 2),
            portals: [],
            interactables: []
        )
        document.maps.append(newMap)
        document.selectedMapIndex = document.maps.count - 1
        statusLine = "ADDED \(newMap.name.uppercased())."
    }

    func duplicateSelectedMap() {
        guard let map = currentMap else { return }
        let duplicate = EditableMap(
            id: "\(map.id)_copy",
            name: "\(map.name) Copy",
            lines: map.lines,
            spawn: map.spawn,
            portals: map.portals,
            interactables: map.interactables
        )
        let insertIndex = min(document.selectedMapIndex + 1, document.maps.count)
        document.maps.insert(duplicate, at: insertIndex)
        document.selectedMapIndex = insertIndex
        statusLine = "DUPLICATED \(map.name.uppercased())."
    }

    func updateFolderName(_ value: String) {
        document.folderName = sanitizeFolderName(value)
    }

    func updateAdventureID(_ value: String) {
        document.adventureID = sanitizeIdentifier(value)
    }

    func updateTitle(_ value: String) {
        document.title = value
    }

    func updateSummary(_ value: String) {
        document.summary = value
    }

    func updateIntroLine(_ value: String) {
        document.introLine = value
    }

    func updateCurrentMapID(_ value: String) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].id = sanitizeIdentifier(value)
    }

    func updateCurrentMapName(_ value: String) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].name = value
    }

    func paintTile(x: Int, y: Int) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].setGlyph(selectedGlyph, atX: x, y: y)
    }

    private func sanitizeIdentifier(_ value: String) -> String {
        let filtered = value
            .lowercased()
            .map { char -> Character in
                if char.isLetter || char.isNumber {
                    return char
                }
                return "_"
            }
        let collapsed = String(filtered)
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "new_adventure" : collapsed
    }

    private func sanitizeFolderName(_ value: String) -> String {
        let safe = sanitizeIdentifier(value)
        return safe.isEmpty ? "new_adventure" : safe
    }

    private static func makeDocument(entry: AdventureCatalogEntry, content: GameContent) -> EditableAdventureDocument {
        let maps = content.maps.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                EditableMap(
                    id: $0.id,
                    name: $0.name,
                    lines: $0.lines,
                    spawn: $0.spawn,
                    portals: $0.portals,
                    interactables: $0.interactables
                )
            }

        let folderName = sourceFolderName(for: entry)
        return EditableAdventureDocument(
            folderName: folderName,
            adventureID: entry.id.rawValue,
            title: content.title,
            summary: content.summary,
            introLine: content.introLine,
            maps: maps,
            selectedMapIndex: 0,
            questFlow: content.questFlow,
            dialogues: content.dialogues.values.sorted { $0.id < $1.id },
            encounters: content.encounters.values.sorted { $0.id < $1.id },
            npcs: content.initialNPCs,
            enemies: content.initialEnemies,
            shops: content.shops.values.sorted { $0.id < $1.id }
        )
    }

    private static func makeBlankDocument() -> EditableAdventureDocument {
        EditableAdventureDocument(
            folderName: "new_adventure",
            adventureID: "new_adventure",
            title: "New Adventure",
            summary: "A custom road beyond the bundled campaigns.",
            introLine: "A fresh path opens beyond the embers.",
            maps: [
                EditableMap(
                    id: "merrow_village",
                    name: "Starter Grounds",
                    lines: makeStarterMapLines(),
                    spawn: Position(x: 2, y: 2),
                    portals: [],
                    interactables: []
                )
            ],
            selectedMapIndex: 0,
            questFlow: QuestFlowDefinition(
                stages: [
                    QuestStageDefinition(
                        objective: "Find the first landmark.",
                        completeWhenFlag: .metElder
                    )
                ],
                completionText: "The first chapter closes."
            ),
            dialogues: [],
            encounters: [],
            npcs: [],
            enemies: [],
            shops: []
        )
    }

    private static func makeStarterMapLines() -> [String] {
        [
            "####################",
            "#..................#",
            "#..................#",
            "#....\"\"\"...........#",
            "#..................#",
            "#...........~~~~...#",
            "#..................#",
            "#..............*...#",
            "#..................#",
            "####################"
        ]
    }

    private static func sourceFolderName(for entry: AdventureCatalogEntry) -> String {
        let value = entry.folder
        if value.contains("/") {
            return URL(fileURLWithPath: value).lastPathComponent
        }
        return value
            .split(separator: "/")
            .last
            .map(String.init) ?? entry.id.rawValue
    }
}

struct EditableAdventureDocument {
    var folderName: String
    var adventureID: String
    var title: String
    var summary: String
    var introLine: String
    var maps: [EditableMap]
    var selectedMapIndex: Int
    var questFlow: QuestFlowDefinition
    var dialogues: [DialogueNode]
    var encounters: [EncounterDefinition]
    var npcs: [NPCState]
    var enemies: [EnemyState]
    var shops: [ShopDefinition]
}

struct EditableMap: Identifiable {
    var id: String
    var name: String
    var lines: [String]
    var spawn: Position
    var portals: [Portal]
    var interactables: [InteractableDefinition]

    mutating func setGlyph(_ glyph: Character, atX x: Int, y: Int) {
        guard y >= 0, y < lines.count else { return }
        var row = Array(lines[y])
        guard x >= 0, x < row.count else { return }
        row[x] = glyph
        lines[y] = String(row)
    }
}

struct AdventurePackExporter {
    private let fileManager: FileManager
    private let externalRootURL: URL

    init(fileManager: FileManager = .default, externalRootURL: URL? = nil) {
        self.fileManager = fileManager
        if let externalRootURL {
            self.externalRootURL = externalRootURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.externalRootURL = appSupport
                .appendingPathComponent("Codexitma", isDirectory: true)
                .appendingPathComponent("Adventures", isDirectory: true)
        }
    }

    func save(document: EditableAdventureDocument) throws -> URL {
        let folderName = sanitizePathComponent(document.folderName.isEmpty ? document.adventureID : document.folderName)
        let packURL = externalRootURL.appendingPathComponent(folderName, isDirectory: true)
        let mapsURL = packURL.appendingPathComponent("maps", isDirectory: true)

        try fileManager.createDirectory(at: mapsURL, withIntermediateDirectories: true)

        let manifest = EditorAdventureManifest(
            id: AdventureID(rawValue: document.adventureID),
            title: document.title,
            summary: document.summary,
            introLine: document.introLine,
            objectivesFile: "quest_flow.json",
            worldFile: "world.json",
            dialoguesFile: "dialogues.json",
            encountersFile: "encounters.json",
            npcsFile: "npcs.json",
            enemiesFile: "enemies.json",
            shopsFile: "shops.json"
        )

        let maps = document.maps.map { map in
            MapDefinition(
                id: map.id,
                name: map.name,
                layoutFile: "maps/\(sanitizePathComponent(map.id)).txt",
                lines: map.lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
        }

        for map in maps {
            let layoutURL = packURL.appendingPathComponent(map.layoutFile)
            let text = map.lines.joined(separator: "\n") + "\n"
            try text.write(to: layoutURL, atomically: true, encoding: .utf8)
        }

        try writeJSON(manifest, to: packURL.appendingPathComponent("adventure.json"))
        try writeJSON(document.questFlow, to: packURL.appendingPathComponent("quest_flow.json"))
        try writeJSON(maps, to: packURL.appendingPathComponent("world.json"))
        try writeJSON(document.dialogues, to: packURL.appendingPathComponent("dialogues.json"))
        try writeJSON(document.encounters, to: packURL.appendingPathComponent("encounters.json"))
        try writeJSON(document.npcs, to: packURL.appendingPathComponent("npcs.json"))
        try writeJSON(document.enemies, to: packURL.appendingPathComponent("enemies.json"))
        try writeJSON(document.shops, to: packURL.appendingPathComponent("shops.json"))

        return packURL
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let filtered = value
            .lowercased()
            .map { char -> Character in
                if char.isLetter || char.isNumber || char == "_" || char == "-" {
                    return char
                }
                return "_"
            }
        let safe = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return safe.isEmpty ? "adventure" : safe
    }
}

private struct EditorAdventureManifest: Codable {
    let id: AdventureID
    let title: String
    let summary: String
    let introLine: String
    let objectivesFile: String
    let worldFile: String
    let dialoguesFile: String
    let encountersFile: String
    let npcsFile: String
    let enemiesFile: String
    let shopsFile: String
}

struct AdventureEditorRootView: View {
    @ObservedObject var store: AdventureEditorStore

    private let palette = AdventureEditorPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 12) {
                header

                HStack(alignment: .top, spacing: 12) {
                    sourcePanel
                        .frame(width: 240)

                    VStack(spacing: 12) {
                        metadataPanel
                        HStack(alignment: .top, spacing: 12) {
                            mapListPanel
                                .frame(width: 240)
                            mapEditorPanel
                        }
                    }
                }

                footer
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack {
            Text("CODEXITMA ADVENTURE EDITOR")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.title)
            Spacer()
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
            }
        }
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

    private var mapEditorPanel: some View {
        EditorPanel(title: "MAP PAINTER", palette: palette) {
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

                    tilePalette

                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array((store.currentMap?.lines ?? []).enumerated()), id: \.offset) { y, line in
                                HStack(spacing: 1) {
                                    ForEach(Array(line.enumerated()), id: \.offset) { x, glyph in
                                        Button {
                                            store.paintTile(x: x, y: y)
                                        } label: {
                                            ZStack {
                                                Rectangle()
                                                    .fill(tileColor(for: glyph))
                                                Text(displayGlyph(glyph))
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(palette.background)
                                            }
                                            .frame(width: 18, height: 18)
                                            .overlay(Rectangle().stroke(palette.border.opacity(0.55), lineWidth: 0.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(6)
                        .background(palette.panelAlt)
                    }
                    .frame(minHeight: 360)
                    .overlay(Rectangle().stroke(palette.border, lineWidth: 1))
                } else {
                    Text("NO MAP IS ACTIVE.")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.text)
                }
            }
        }
    }

    private var tilePalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TILE PALETTE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)

            HStack(spacing: 6) {
                ForEach(editorTilePalette, id: \.glyph) { tile in
                    Button {
                        store.selectedGlyph = tile.glyph
                    } label: {
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
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
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

private struct AdventureEditorPalette {
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

private struct EditorPanel<Content: View>: View {
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

private struct EditorButtonStyle: ButtonStyle {
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

private struct EditorTileChoice {
    let glyph: Character
    let label: String
}

private let editorTilePalette: [EditorTileChoice] = [
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
