import Foundation

struct AdventureEditorSceneSnapshot {
    let adventureID: String
    let title: String
    let folderName: String
    let currentMapID: String
    let currentMapName: String
    let mapLines: [String]
    let cursor: Position
    let selectedTool: EditorTool
    let selectedGlyph: Character
    let selectedContentTab: EditorContentTab
    let selectionSummaryLines: [String]
    let validationMessages: [String]
    let statusLine: String
}

@MainActor
final class AdventureEditorSession {
    let store: AdventureEditorStore
    private(set) var cursor: Position

    init(
        library: GameContentLibrary,
        initialAdventureID: AdventureID? = nil,
        exporter: AdventurePackExporter = AdventurePackExporter(),
        playtestLauncher: @MainActor @escaping (AdventureID) throws -> Void = AdventureEditorStore.defaultPlaytestLauncher
    ) {
        self.store = AdventureEditorStore(
            library: library,
            exporter: exporter,
            playtestLauncher: playtestLauncher
        )
        if let initialAdventureID {
            self.store.selectCatalogAdventure(initialAdventureID)
        }
        self.cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
    }

    var sceneSnapshot: AdventureEditorSceneSnapshot {
        let map = store.currentMap
        return AdventureEditorSceneSnapshot(
            adventureID: store.document.adventureID,
            title: store.document.title,
            folderName: store.document.folderName,
            currentMapID: map?.id ?? "",
            currentMapName: map?.name ?? "",
            mapLines: map?.lines ?? [],
            cursor: cursor,
            selectedTool: store.selectedTool,
            selectedGlyph: store.selectedGlyph,
            selectedContentTab: store.selectedContentTab,
            selectionSummaryLines: store.selectionSummaryLines,
            validationMessages: store.validationMessages,
            statusLine: store.statusLine
        )
    }

    func selectAdventure(_ adventureID: AdventureID) {
        store.selectCatalogAdventure(adventureID)
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
    }

    func createBlankAdventure() {
        store.createBlankAdventure()
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
    }

    func moveCursor(_ direction: Direction) {
        switch direction {
        case .up:
            cursor.y -= 1
        case .down:
            cursor.y += 1
        case .left:
            cursor.x -= 1
        case .right:
            cursor.x += 1
        }
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func setCursor(_ position: Position) {
        cursor = position
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func centerCursorOnSpawn() {
        cursor = store.currentMap?.spawn ?? Position(x: 0, y: 0)
        clampCursor()
        store.selectCanvasObject(at: cursor)
    }

    func applyCurrentTool() {
        store.handleCanvasClick(x: cursor.x, y: cursor.y)
    }

    func cycleTool(step: Int = 1) {
        let tools = EditorTool.allCases
        guard let currentIndex = tools.firstIndex(of: store.selectedTool) else { return }
        let nextIndex = wrappedIndex(currentIndex + step, count: tools.count)
        store.selectTool(tools[nextIndex])
    }

    func cycleContentTab(step: Int = 1) {
        let tabs = EditorContentTab.allCases
        guard let currentIndex = tabs.firstIndex(of: store.selectedContentTab) else { return }
        let nextIndex = wrappedIndex(currentIndex + step, count: tabs.count)
        store.selectContentTab(tabs[nextIndex])
    }

    func cycleMap(step: Int = 1) {
        let count = store.document.maps.count
        guard count > 0 else { return }
        let nextIndex = wrappedIndex(store.document.selectedMapIndex + step, count: count)
        store.selectMap(index: nextIndex)
        centerCursorOnSpawn()
    }

    private func clampCursor() {
        guard let map = store.currentMap, let width = map.lines.first?.count, width > 0 else {
            cursor = Position(x: 0, y: 0)
            return
        }
        cursor.x = max(0, min(cursor.x, width - 1))
        cursor.y = max(0, min(cursor.y, map.lines.count - 1))
    }

    private func wrappedIndex(_ rawIndex: Int, count: Int) -> Int {
        let remainder = rawIndex % count
        return remainder >= 0 ? remainder : remainder + count
    }
}
