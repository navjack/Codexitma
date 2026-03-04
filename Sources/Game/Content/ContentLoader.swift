import Foundation

enum ContentError: Error {
    case missingResource(String)
    case invalidMap(String)
}

private struct AdventurePackDefinition: Decodable {
    let id: AdventureID?
    let title: String?
    let summary: String?
    let introLine: String?
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

        for entry in adventureCatalogEntries {
            let pack: AdventurePackDefinition = try decodeJSON(entry.packFile, from: .bundled(subdirectory: entry.folder))
            let content = try buildContent(from: pack, entry: entry, source: .bundled(subdirectory: entry.folder))
            catalog.append(entry)
            adventures[entry.id] = content
        }

        for entry in try loadExternalAdventureEntries() {
            let pack: AdventurePackDefinition = try decodeJSON("adventure.json", from: .filesystem(baseURL: externalPackURL(for: entry)))
            let content = try buildContent(from: pack, entry: entry, source: .filesystem(baseURL: externalPackURL(for: entry)))
            if let existingIndex = catalog.firstIndex(where: { $0.id == entry.id }) {
                catalog[existingIndex] = entry
            } else {
                catalog.append(entry)
            }
            adventures[entry.id] = content
        }

        return GameContentLibrary(catalog: catalog, adventures: adventures)
    }

    private func buildContent(
        from pack: AdventurePackDefinition,
        entry: AdventureCatalogEntry,
        source: ContentSource
    ) throws -> GameContent {
        let maps = try loadMaps(file: pack.worldFile, from: source)
        let dialogues = keyedByID(try decodeJSON([DialogueNode].self, file: pack.dialoguesFile, from: source))
        let encounters = keyedByID(try decodeJSON([EncounterDefinition].self, file: pack.encountersFile, from: source))
        let shops = keyedByMerchant(try decodeJSON([ShopDefinition].self, file: pack.shopsFile, from: source))
        let questFlow: QuestFlowDefinition = try decodeJSON(pack.objectivesFile, from: source)
        let npcs: [NPCState] = try decodeJSON(pack.npcsFile, from: source)
        let enemies: [EnemyState] = try decodeJSON(pack.enemiesFile, from: source)

        return GameContent(
            id: entry.id,
            title: entry.title,
            summary: entry.summary,
            introLine: entry.introLine,
            questFlow: questFlow,
            maps: maps,
            dialogues: dialogues,
            encounters: encounters,
            items: itemTable,
            shops: shops,
            initialNPCs: npcs,
            initialEnemies: enemies
        )
    }

    private func loadMaps(file: String, from source: ContentSource) throws -> [String: MapDefinition] {
        let maps: [MapDefinition] = try decodeJSON(file, from: source)

        var resolvedMaps: [String: MapDefinition] = [:]
        for map in maps {
            let raw = try loadTextResource(map.layoutFile, from: source)
            let lines = raw
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
            let resolved = MapDefinition(
                id: map.id,
                name: map.name,
                layoutFile: map.layoutFile,
                lines: lines,
                spawn: map.spawn,
                portals: map.portals,
                interactables: map.interactables
            )
            try validate(map: resolved)
            resolvedMaps[resolved.id] = resolved
        }
        return resolvedMaps
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

    private func loadTextResource(_ file: String, from source: ContentSource) throws -> String {
        if let url = resourceURL(for: file, from: source) {
            return try String(contentsOf: url)
        }
        throw ContentError.missingResource(file)
    }

    private func decodeJSON<T: Decodable>(_ file: String, from source: ContentSource) throws -> T {
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
        let descriptor = ResourceDescriptor(file: file)
        let nestedBase = descriptor.nestedSubdirectory.map { baseURL.appendingPathComponent($0, isDirectory: true) } ?? baseURL
        let fileName = descriptor.fileExtension.map { "\(descriptor.baseName).\($0)" } ?? descriptor.baseName
        let url = nestedBase.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
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

    private func loadExternalAdventureEntries() throws -> [AdventureCatalogEntry] {
        let root = externalAdventureRoot()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var entries: [AdventureCatalogEntry] = []

        for folder in folders {
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let manifestURL = folder.appendingPathComponent("adventure.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

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
        }

        return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func externalAdventureRoot() -> URL {
        if let externalRootURL {
            return externalRootURL
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("Codexitma", isDirectory: true)
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
