import Foundation

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

    func validate(document: EditableAdventureDocument) -> [String] {
        var issues: [String] = []
        let loader = ContentLoader()

        if document.folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Folder name cannot be empty.")
        }
        if document.adventureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Adventure ID cannot be empty.")
        }
        if document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Adventure title cannot be empty.")
        }
        if document.maps.isEmpty {
            issues.append("At least one map is required.")
        }
        if document.questFlow.stages.isEmpty {
            issues.append("At least one quest stage is required.")
        }
        if document.dialogues.isEmpty {
            issues.append("At least one dialogue is required.")
        }

        issues.append(contentsOf: duplicateIDIssues(for: document.maps.map(\.id), label: "map"))
        issues.append(contentsOf: duplicateIDIssues(for: document.dialogues.map(\.id), label: "dialogue"))
        issues.append(contentsOf: duplicateIDIssues(for: document.encounters.map(\.id), label: "encounter"))
        issues.append(contentsOf: duplicateIDIssues(for: document.npcs.map(\.id), label: "npc"))
        issues.append(contentsOf: duplicateIDIssues(for: document.enemies.map(\.id), label: "enemy"))
        issues.append(contentsOf: duplicateIDIssues(for: document.shops.map(\.id), label: "shop"))

        var mapsByID: [String: EditableMap] = [:]
        for map in document.maps {
            mapsByID[map.id] = map
        }

        for map in document.maps {
            let mapDefinition = MapDefinition(
                id: map.id,
                name: map.name,
                layoutFile: "maps/\(sanitizePathComponent(map.id)).txt",
                lines: map.lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
            do {
                try loader.validate(map: mapDefinition)
            } catch {
                issues.append("Map \(map.id) has invalid layout data.")
            }

            if !contains(position: map.spawn, in: map) {
                issues.append("Map \(map.id) has a spawn outside its bounds.")
            } else if !isWalkable(position: map.spawn, in: map) {
                issues.append("Map \(map.id) spawn must be on a walkable tile.")
            }

            issues.append(contentsOf: duplicateIDIssues(for: map.interactables.map(\.id), label: "interactable in \(map.id)"))

            for interactable in map.interactables {
                if !contains(position: interactable.position, in: map) {
                    issues.append("Interactable \(interactable.id) is outside \(map.id).")
                }
                if let marks = interactable.rewardMarks, marks < 0 {
                    issues.append("Interactable \(interactable.id) cannot award negative marks.")
                }
            }

            for portal in map.portals {
                if !contains(position: portal.from, in: map) {
                    issues.append("A portal in \(map.id) starts outside the map.")
                }
                if portal.requiredFlag != nil,
                   (portal.blockedMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    issues.append("A gated portal in \(map.id) needs blocked text.")
                }
                guard let destinationMap = mapsByID[portal.toMap] else {
                    issues.append("A portal in \(map.id) points to missing map \(portal.toMap).")
                    continue
                }
                if !contains(position: portal.toPosition, in: destinationMap) {
                    issues.append("A portal in \(map.id) lands outside \(portal.toMap).")
                }
            }
        }

        let dialogueIDs = Set(document.dialogues.map(\.id))
        for npc in document.npcs {
            guard let map = mapsByID[npc.mapID] else {
                issues.append("NPC \(npc.id) points to missing map \(npc.mapID).")
                continue
            }
            if !contains(position: npc.position, in: map) {
                issues.append("NPC \(npc.id) is outside \(npc.mapID).")
            }
            if !dialogueIDs.contains(npc.dialogueID) {
                issues.append("NPC \(npc.id) points to missing dialogue \(npc.dialogueID).")
            }
        }

        let enemyIDs = Set(document.enemies.map(\.id))
        for enemy in document.enemies {
            guard let map = mapsByID[enemy.mapID] else {
                issues.append("Enemy \(enemy.id) points to missing map \(enemy.mapID).")
                continue
            }
            if !contains(position: enemy.position, in: map) {
                issues.append("Enemy \(enemy.id) is outside \(enemy.mapID).")
            }
        }

        for encounter in document.encounters {
            if !enemyIDs.contains(encounter.enemyID) {
                issues.append("Encounter \(encounter.id) points to missing enemy \(encounter.enemyID).")
            }
        }

        let npcIDs = Set(document.npcs.map(\.id))
        var allOfferIDs: [String] = []
        for shop in document.shops {
            if !npcIDs.contains(shop.merchantID) {
                issues.append("Shop \(shop.id) points to missing merchant \(shop.merchantID).")
            }
            if shop.offers.isEmpty {
                issues.append("Shop \(shop.id) must have at least one offer.")
            }
            for offer in shop.offers {
                if offer.price < 0 {
                    issues.append("Shop offer \(offer.id) cannot have a negative price.")
                }
                allOfferIDs.append(offer.id)
            }
        }
        issues.append(contentsOf: duplicateIDIssues(for: allOfferIDs, label: "shop offer"))

        return issues
    }

    func save(document: EditableAdventureDocument) throws -> URL {
        let issues = validate(document: document)
        if !issues.isEmpty {
            throw AdventurePackValidationError(issues: issues)
        }

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

    private func duplicateIDIssues(for ids: [String], label: String) -> [String] {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for id in ids {
            if !seen.insert(id).inserted {
                duplicates.insert(id)
            }
        }
        return duplicates.sorted().map { "Duplicate \(label) id: \($0)." }
    }

    private func contains(position: Position, in map: EditableMap) -> Bool {
        guard position.y >= 0, position.y < map.lines.count else { return false }
        let row = Array(map.lines[position.y])
        return position.x >= 0 && position.x < row.count
    }

    private func isWalkable(position: Position, in map: EditableMap) -> Bool {
        guard contains(position: position, in: map) else { return false }
        let row = Array(map.lines[position.y])
        return TileFactory.tile(for: row[position.x]).walkable
    }
}

struct AdventurePackValidationError: LocalizedError {
    let issues: [String]

    var errorDescription: String? {
        issues.joined(separator: " | ")
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
