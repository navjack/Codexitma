import Foundation

extension AdventureEditorStore {
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
        resetSecondarySelections()
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        validationMessages = []
        statusLine = "LOADED \(entry.title.uppercased()) FOR EDITING."
    }

    func createBlankAdventure() {
        selectedCatalogID = nil
        document = Self.makeBlankDocument()
        resetSecondarySelections()
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        validationMessages = []
        statusLine = "BLANK TEMPLATE CREATED. SAVE IT TO EXPORT A NEW ADVENTURE PACK."
    }

    @discardableResult
    func validateCurrentPack() -> Bool {
        let issues = exporter.validate(document: document)
        validationMessages = issues
        if issues.isEmpty {
            statusLine = "VALIDATION CLEAN. THE PACK IS READY TO EXPORT."
            return true
        }
        statusLine = "VALIDATION FAILED: \(issues.count) ISSUE(S)."
        return false
    }

    func saveCurrentPack() {
        guard validateCurrentPack() else { return }
        do {
            let exportedURL = try exporter.save(document: document)
            statusLine = "EXPORTED TO \(exportedURL.path.uppercased())"
        } catch {
            statusLine = "EXPORT FAILED: \(String(describing: error).uppercased())"
        }
    }

    func saveAndPlaytestCurrentPack() {
        guard validateCurrentPack() else { return }
        do {
            _ = try exporter.save(document: document)
            try playtestLauncher(AdventureID(rawValue: document.adventureID))
            statusLine = "PLAYTEST LAUNCHED FOR \(document.title.uppercased())."
        } catch {
            statusLine = "PLAYTEST FAILED: \(String(describing: error).uppercased())"
        }
    }

    func selectContentTab(_ tab: EditorContentTab) {
        selectedContentTab = tab
        statusLine = "\(tab.title.uppercased()) TAB READY."
    }

    func selectMap(index: Int) {
        guard !document.maps.isEmpty else { return }
        document.selectedMapIndex = max(0, min(index, document.maps.count - 1))
        selectedContentTab = .maps
        selectedCanvasSelection = nil
        statusLine = "EDITING \(document.maps[document.selectedMapIndex].name.uppercased())."
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
        let oldID = document.maps[document.selectedMapIndex].id
        let newID = sanitizeIdentifier(value)
        document.maps[document.selectedMapIndex].id = newID
        if oldID != newID {
            for index in document.npcs.indices where document.npcs[index].mapID == oldID {
                document.npcs[index].mapID = newID
            }
            for index in document.enemies.indices where document.enemies[index].mapID == oldID {
                document.enemies[index].mapID = newID
            }
            for mapIndex in document.maps.indices {
                for portalIndex in document.maps[mapIndex].portals.indices {
                    if document.maps[mapIndex].portals[portalIndex].toMap == oldID {
                        let portal = document.maps[mapIndex].portals[portalIndex]
                        document.maps[mapIndex].portals[portalIndex] = Portal(
                            from: portal.from,
                            toMap: newID,
                            toPosition: portal.toPosition,
                            requiredFlag: portal.requiredFlag,
                            blockedMessage: portal.blockedMessage
                        )
                    }
                }
            }
        }
    }

    func updateCurrentMapName(_ value: String) {
        guard !document.maps.isEmpty else { return }
        document.maps[document.selectedMapIndex].name = value
    }
}
