import Foundation

enum ContentError: Error, LocalizedError {
    case missingResource(String)
    case invalidMap(String)
    case invalidPack(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let file):
            return "Missing resource: \(file)"
        case .invalidMap(let id):
            return "Invalid map: \(id)"
        case .invalidPack(let message):
            return "Invalid adventure pack: \(message)"
        }
    }
}

private struct AdventurePackDefinition: Decodable {
    let id: AdventureID?
    let title: String?
    let summary: String?
    let introLine: String?
    let startMapID: String?
    let objectivesFile: String
    let worldFile: String
    let dialoguesFile: String
    let encountersFile: String
    let npcsFile: String
    let enemiesFile: String
    let shopsFile: String
}

private enum ContentSource {
    case bundled(subdirectory: String)
    case filesystem(baseURL: URL)
}

private struct ResourceDescriptor {
    let baseName: String
    let fileExtension: String?
    let nestedSubdirectory: String?

    init(file: String) {
        let nsFile = file as NSString
        let pathDirectory = nsFile.deletingLastPathComponent
        let lastPath = nsFile.lastPathComponent
        let nsLastPath = lastPath as NSString
        let rawExtension = nsLastPath.pathExtension
        let rawBaseName = nsLastPath.deletingPathExtension

        self.baseName = rawExtension.isEmpty ? lastPath : rawBaseName
        self.fileExtension = rawExtension.isEmpty ? nil : rawExtension
        self.nestedSubdirectory = pathDirectory.isEmpty ? nil : pathDirectory
    }
}

private struct LoadedMaps {
    let byID: [String: MapDefinition]
    let orderedIDs: [String]
}

private struct ExternalPackScan {
    let entries: [AdventureCatalogEntry]
    let warnings: [String]
}

struct ContentLoader {
    private let fileManager: FileManager
    private let externalRootURL: URL?

    init(fileManager: FileManager = .default, externalRootURL: URL? = nil) {
        self.fileManager = fileManager
        self.externalRootURL = externalRootURL
    }

    func load() throws -> GameContentLibrary {
        var catalog: [AdventureCatalogEntry] = []
        var adventures: [AdventureID: GameContent] = [:]
        var warnings: [String] = []

        for entry in adventureCatalogEntries {
            let pack: AdventurePackDefinition = try decodeJSON(entry.packFile, from: .bundled(subdirectory: entry.folder))
            let content = try buildContent(from: pack, entry: entry, source: .bundled(subdirectory: entry.folder))
            catalog.append(entry)
            adventures[entry.id] = content
        }

        let externalScan = try loadExternalAdventureEntries()
        warnings.append(contentsOf: externalScan.warnings)

        for entry in externalScan.entries {
            do {
                let baseURL = externalPackURL(for: entry)
                let pack: AdventurePackDefinition = try decodeJSON("adventure.json", from: .filesystem(baseURL: baseURL))
                let content = try buildContent(from: pack, entry: entry, source: .filesystem(baseURL: baseURL))
                if let existingIndex = catalog.firstIndex(where: { $0.id == entry.id }) {
                    catalog[existingIndex] = entry
                } else {
                    catalog.append(entry)
                }
                adventures[entry.id] = content
            } catch {
                warnings.append("Skipped external pack \(entry.title): \(error)")
            }
        }

        return GameContentLibrary(catalog: catalog, adventures: adventures, loadWarnings: warnings)
    }

    private func buildContent(
        from pack: AdventurePackDefinition,
        entry: AdventureCatalogEntry,
        source: ContentSource
    ) throws -> GameContent {
        let loadedMaps = try loadMaps(file: pack.worldFile, from: source)
        let dialogues = keyedByID(try decodeJSON([DialogueNode].self, file: pack.dialoguesFile, from: source))
        let encounters = keyedByID(try decodeJSON([EncounterDefinition].self, file: pack.encountersFile, from: source))
        let shops = keyedByMerchant(try decodeJSON([ShopDefinition].self, file: pack.shopsFile, from: source))
        let questFlow: QuestFlowDefinition = try decodeJSON(pack.objectivesFile, from: source)
        let npcs: [NPCState] = try decodeJSON(pack.npcsFile, from: source)
        let enemies: [EnemyState] = try decodeJSON(pack.enemiesFile, from: source)
        let startMapID = try resolveStartMapID(requested: pack.startMapID, maps: loadedMaps)
        try validateContent(
            maps: loadedMaps.byID,
            startMapID: startMapID,
            dialogues: dialogues,
            encounters: encounters,
            npcs: npcs,
            enemies: enemies,
            shops: shops
        )

        return GameContent(
            id: entry.id,
            title: entry.title,
            summary: entry.summary,
            introLine: entry.introLine,
            startMapID: startMapID,
            questFlow: questFlow,
            maps: loadedMaps.byID,
            dialogues: dialogues,
            encounters: encounters,
            items: itemTable,
            shops: shops,
            initialNPCs: npcs,
            initialEnemies: enemies
        )
    }

    private func loadMaps(file: String, from source: ContentSource) throws -> LoadedMaps {
        let maps: [MapDefinition] = try decodeJSON(file, from: source)

        var resolvedMaps: [String: MapDefinition] = [:]
        var orderedIDs: [String] = []
        for map in maps {
            let raw = try loadTextResource(map.layoutFile, from: source)
            let lines = raw
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            let resolved = MapDefinition(
                id: map.id,
                name: map.name,
                depthBackdrop: map.depthBackdrop,
                layoutFile: map.layoutFile,
                lines: lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
            try validate(map: resolved)
            resolvedMaps[resolved.id] = resolved
            orderedIDs.append(resolved.id)
        }
        return LoadedMaps(byID: resolvedMaps, orderedIDs: orderedIDs)
    }

    func validate(map: MapDefinition) throws {
        guard let first = map.lines.first else { throw ContentError.invalidMap(map.id) }
        let width = first.count
        for line in map.lines {
            guard line.count == width else { throw ContentError.invalidMap(map.id) }
            for char in line {
                guard TileFactory.isAllowedGlyph(char) else { throw ContentError.invalidMap(map.id) }
            }
        }
    }

    private func resolveStartMapID(requested: String?, maps: LoadedMaps) throws -> String {
        if let requested {
            guard maps.byID[requested] != nil else {
                throw ContentError.invalidPack("Start map \(requested) is missing.")
            }
            return requested
        }
        if maps.byID["merrow_village"] != nil {
            return "merrow_village"
        }
        if let first = maps.orderedIDs.first {
            return first
        }
        throw ContentError.invalidPack("Adventure has no maps.")
    }

    private func validateContent(
        maps: [String: MapDefinition],
        startMapID: String,
        dialogues: [String: DialogueNode],
        encounters: [String: EncounterDefinition],
        npcs: [NPCState],
        enemies: [EnemyState],
        shops: [NPCID: ShopDefinition]
    ) throws {
        guard let startMap = maps[startMapID] else {
            throw ContentError.invalidPack("Start map \(startMapID) is missing.")
        }
        guard contains(position: startMap.spawn, in: startMap), isWalkable(position: startMap.spawn, in: startMap) else {
            throw ContentError.invalidPack("Start map \(startMapID) has an invalid spawn.")
        }

        var globalInteractableIDs: Set<String> = []
        let mapIDs = Set(maps.keys)
        let dialogueIDs = Set(dialogues.keys)
        let enemyIDs = Set(enemies.map(\.id))
        let npcIDs = Set(npcs.map(\.id))

        for map in maps.values {
            guard contains(position: map.spawn, in: map), isWalkable(position: map.spawn, in: map) else {
                throw ContentError.invalidPack("Map \(map.id) has an invalid spawn.")
            }

            for interactable in map.interactables {
                guard contains(position: interactable.position, in: map) else {
                    throw ContentError.invalidPack("Interactable \(interactable.id) sits outside \(map.id).")
                }
                if let marks = interactable.rewardMarks, marks < 0 {
                    throw ContentError.invalidPack("Interactable \(interactable.id) cannot award negative marks.")
                }
                guard globalInteractableIDs.insert(interactable.id).inserted else {
                    throw ContentError.invalidPack("Duplicate interactable id \(interactable.id).")
                }
            }

            for portal in map.portals {
                guard contains(position: portal.from, in: map) else {
                    throw ContentError.invalidPack("A portal in \(map.id) starts outside the map.")
                }
                guard mapIDs.contains(portal.toMap), let destinationMap = maps[portal.toMap] else {
                    throw ContentError.invalidPack("A portal in \(map.id) points to missing map \(portal.toMap).")
                }
                guard contains(position: portal.toPosition, in: destinationMap) else {
                    throw ContentError.invalidPack("A portal in \(map.id) lands outside \(portal.toMap).")
                }
                if portal.requiredFlag != nil,
                   (portal.blockedMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    throw ContentError.invalidPack("A gated portal in \(map.id) needs blocked text.")
                }
            }
        }

        for npc in npcs {
            guard let map = maps[npc.mapID] else {
                throw ContentError.invalidPack("NPC \(npc.id) points to missing map \(npc.mapID).")
            }
            guard contains(position: npc.position, in: map) else {
                throw ContentError.invalidPack("NPC \(npc.id) sits outside \(npc.mapID).")
            }
            guard dialogueIDs.contains(npc.dialogueID) else {
                throw ContentError.invalidPack("NPC \(npc.id) points to missing dialogue \(npc.dialogueID).")
            }
        }

        for enemy in enemies {
            guard let map = maps[enemy.mapID] else {
                throw ContentError.invalidPack("Enemy \(enemy.id) points to missing map \(enemy.mapID).")
            }
            guard contains(position: enemy.position, in: map) else {
                throw ContentError.invalidPack("Enemy \(enemy.id) sits outside \(enemy.mapID).")
            }
        }

        for encounter in encounters.values {
            guard enemyIDs.contains(encounter.enemyID) else {
                throw ContentError.invalidPack("Encounter \(encounter.id) points to missing enemy \(encounter.enemyID).")
            }
        }
        let encounterEnemyIDs = encounters.values.map(\.enemyID)
        if Set(encounterEnemyIDs).count != encounterEnemyIDs.count {
            throw ContentError.invalidPack("Encounter enemy bindings must be unique.")
        }

        var seenOfferIDs: Set<String> = []
        for shop in shops.values {
            guard npcIDs.contains(shop.merchantID) else {
                throw ContentError.invalidPack("Shop \(shop.id) points to missing merchant \(shop.merchantID).")
            }
            guard !shop.offers.isEmpty else {
                throw ContentError.invalidPack("Shop \(shop.id) must have at least one offer.")
            }
            for offer in shop.offers {
                guard offer.price >= 0 else {
                    throw ContentError.invalidPack("Shop offer \(offer.id) cannot have a negative price.")
                }
                guard seenOfferIDs.insert(offer.id).inserted else {
                    throw ContentError.invalidPack("Duplicate shop offer id \(offer.id).")
                }
            }
        }
    }

    private func loadTextResource(_ file: String, from source: ContentSource) throws -> String {
        try validateExternalResourcePathIfNeeded(file, from: source)
        if let url = resourceURL(for: file, from: source) {
            return try String(contentsOf: url)
        }
        throw ContentError.missingResource(file)
    }

    private func decodeJSON<T: Decodable>(_ file: String, from source: ContentSource) throws -> T {
        try validateExternalResourcePathIfNeeded(file, from: source)
        guard let url = resourceURL(for: file, from: source) else {
            throw ContentError.missingResource(file)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, file: String, from source: ContentSource) throws -> T {
        try decodeJSON(file, from: source)
    }

    private func resourceURL(for file: String, from source: ContentSource) -> URL? {
        switch source {
        case .bundled(let subdirectory):
            return bundledResourceURL(for: file, preferredSubdirectory: subdirectory)
        case .filesystem(let baseURL):
            return filesystemResourceURL(for: file, baseURL: baseURL)
        }
    }

    private func bundledResourceURL(for file: String, preferredSubdirectory: String?) -> URL? {
        let descriptor = ResourceDescriptor(file: file)
        let nestedPreferred = join(preferredSubdirectory, descriptor.nestedSubdirectory)
        let searchPaths = [
            nestedPreferred,
            descriptor.nestedSubdirectory,
            "maps",
            nil,
        ]

        for path in searchPaths {
            if let url = resourceURL(
                baseName: descriptor.baseName,
                fileExtension: descriptor.fileExtension,
                bundle: GameResourceBundle.current,
                exactSubdirectory: path
            ) {
                return url
            }
        }
        return nil
    }

    private func filesystemResourceURL(for file: String, baseURL: URL) -> URL? {
        guard isSafeRelativeResourcePath(file) else { return nil }

        let candidateURL = baseURL.appendingPathComponent(file, isDirectory: false)
        let packRoot = baseURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolvedURL, of: packRoot) else {
            return nil
        }
        return fileManager.fileExists(atPath: resolvedURL.path) ? resolvedURL : nil
    }

    private func resourceURL(
        baseName: String,
        fileExtension: String?,
        bundle: Bundle,
        exactSubdirectory: String?
    ) -> URL? {
        if let exactSubdirectory {
            return bundle.url(forResource: baseName, withExtension: fileExtension, subdirectory: exactSubdirectory)
        }
        return bundle.url(forResource: baseName, withExtension: fileExtension)
    }

    private func join(_ first: String?, _ second: String?) -> String? {
        switch (first, second) {
        case let (lhs?, rhs?):
            return "\(lhs)/\(rhs)"
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func keyedByID<T>(_ values: [T]) -> [String: T] where T: HasStringIdentifier {
        Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private func keyedByMerchant(_ values: [ShopDefinition]) -> [NPCID: ShopDefinition] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.merchantID, $0) })
    }

    private func loadExternalAdventureEntries() throws -> ExternalPackScan {
        let root = externalAdventureRoot()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var entries: [AdventureCatalogEntry] = []
        var warnings: [String] = []

        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let manifestURL = folder.appendingPathComponent("adventure.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

            do {
                let data = try Data(contentsOf: manifestURL)
                let pack = try JSONDecoder().decode(AdventurePackDefinition.self, from: data)
                let fallbackSlug = folder.lastPathComponent
                let entry = AdventureCatalogEntry(
                    id: pack.id ?? AdventureID(rawValue: fallbackSlug),
                    folder: folder.path,
                    packFile: "adventure.json",
                    title: pack.title ?? humanize(slug: fallbackSlug),
                    summary: pack.summary ?? "An external adventure pack loaded from the player content folder.",
                    introLine: pack.introLine ?? "A distant road opens beyond the known maps."
                )
                entries.append(entry)
            } catch {
                warnings.append("Skipped external pack \(folder.lastPathComponent): \(error)")
            }
        }

        return ExternalPackScan(
            entries: entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
            warnings: warnings
        )
    }

    private func externalAdventureRoot() -> URL {
        if let externalRootURL {
            return externalRootURL
        }
        return CodexitmaPaths.dataRoot(fileManager: fileManager)
            .appendingPathComponent("Adventures", isDirectory: true)
    }

    private func externalPackURL(for entry: AdventureCatalogEntry) -> URL {
        URL(fileURLWithPath: entry.folder, isDirectory: true)
    }

    private func humanize(slug: String) -> String {
        slug
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func validateExternalResourcePathIfNeeded(_ file: String, from source: ContentSource) throws {
        guard case .filesystem = source else { return }
        guard isSafeRelativeResourcePath(file) else {
            throw ContentError.invalidPack("Unsafe external resource path: \(file)")
        }
    }

    private func contains(position: Position, in map: MapDefinition) -> Bool {
        guard position.y >= 0, position.y < map.lines.count else { return false }
        let row = Array(map.lines[position.y])
        return position.x >= 0 && position.x < row.count
    }

    private func isWalkable(position: Position, in map: MapDefinition) -> Bool {
        guard contains(position: position, in: map) else { return false }
        let row = Array(map.lines[position.y])
        return TileFactory.tile(for: row[position.x]).walkable
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }

    private func isSafeRelativeResourcePath(_ file: String) -> Bool {
        guard !file.isEmpty else { return false }
        if (file as NSString).isAbsolutePath {
            return false
        }
        if file.hasPrefix("/") || file.hasPrefix("\\") || file.hasPrefix("~") {
            return false
        }
        if file.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }
}

private protocol HasStringIdentifier {
    var id: String { get }
}

extension DialogueNode: HasStringIdentifier {}
extension EncounterDefinition: HasStringIdentifier {}

let itemTable: [ItemID: Item] = {
    let descriptor = ResourceDescriptor(file: "items.json")
    guard let url = GameResourceBundle.current.url(forResource: descriptor.baseName, withExtension: descriptor.fileExtension) else {
        preconditionFailure("Missing items.json in bundled resources.")
    }

    do {
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([Item].self, from: data)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    } catch {
        preconditionFailure("Failed to decode items.json: \(error)")
    }
}()
