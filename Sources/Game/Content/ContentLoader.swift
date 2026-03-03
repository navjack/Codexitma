import Foundation

enum ContentError: Error {
    case missingResource(String)
    case invalidMap(String)
}

private struct AdventurePackDefinition: Decodable {
    let objectivesFile: String
    let worldFile: String
    let dialoguesFile: String
    let encountersFile: String
    let npcsFile: String
    let enemiesFile: String
    let shopsFile: String
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
    func load() throws -> GameContentLibrary {
        let bundle = Bundle.module
        var adventures: [AdventureID: GameContent] = [:]

        for entry in adventureCatalogEntries {
            let pack: AdventurePackDefinition = try decodeJSON(entry.packFile, bundle: bundle, subdirectory: entry.folder)
            let maps = try loadMaps(file: pack.worldFile, bundle: bundle, subdirectory: entry.folder)
            let dialogues = keyedByID(try decodeJSON([DialogueNode].self, file: pack.dialoguesFile, bundle: bundle, subdirectory: entry.folder))
            let encounters = keyedByID(try decodeJSON([EncounterDefinition].self, file: pack.encountersFile, bundle: bundle, subdirectory: entry.folder))
            let shops = keyedByMerchant(try decodeJSON([ShopDefinition].self, file: pack.shopsFile, bundle: bundle, subdirectory: entry.folder))
            let objectives: ObjectiveTextSet = try decodeJSON(pack.objectivesFile, bundle: bundle, subdirectory: entry.folder)
            let npcs: [NPCState] = try decodeJSON(pack.npcsFile, bundle: bundle, subdirectory: entry.folder)
            let enemies: [EnemyState] = try decodeJSON(pack.enemiesFile, bundle: bundle, subdirectory: entry.folder)

            let content = GameContent(
                id: entry.id,
                title: entry.title,
                summary: entry.summary,
                introLine: entry.introLine,
                objectiveText: objectives,
                maps: maps,
                dialogues: dialogues,
                encounters: encounters,
                items: itemTable,
                shops: shops,
                initialNPCs: npcs,
                initialEnemies: enemies
            )
            adventures[entry.id] = content
        }

        return GameContentLibrary(adventures: adventures)
    }

    private func loadMaps(file: String, bundle: Bundle, subdirectory: String) throws -> [String: MapDefinition] {
        let maps: [MapDefinition] = try decodeJSON(file, bundle: bundle, subdirectory: subdirectory)

        var resolvedMaps: [String: MapDefinition] = [:]
        for map in maps {
            let raw = try loadTextResource(map.layoutFile, bundle: bundle, preferredSubdirectory: subdirectory)
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

    private func loadTextResource(_ file: String, bundle: Bundle, preferredSubdirectory: String?) throws -> String {
        if let url = resourceURL(for: file, bundle: bundle, preferredSubdirectory: preferredSubdirectory) {
            return try String(contentsOf: url)
        }
        throw ContentError.missingResource(file)
    }

    private func decodeJSON<T: Decodable>(_ file: String, bundle: Bundle, subdirectory: String?) throws -> T {
        guard let url = resourceURL(for: file, bundle: bundle, preferredSubdirectory: subdirectory) else {
            throw ContentError.missingResource(file)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, file: String, bundle: Bundle, subdirectory: String?) throws -> T {
        try decodeJSON(file, bundle: bundle, subdirectory: subdirectory)
    }

    private func resourceURL(for file: String, bundle: Bundle, preferredSubdirectory: String?) -> URL? {
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
                bundle: bundle,
                exactSubdirectory: path
            ) {
                return url
            }
        }
        return nil
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
}

private protocol HasStringIdentifier {
    var id: String { get }
}

extension DialogueNode: HasStringIdentifier {}
extension EncounterDefinition: HasStringIdentifier {}

let itemTable: [ItemID: Item] = {
    let descriptor = ResourceDescriptor(file: "items.json")
    guard let url = Bundle.module.url(forResource: descriptor.baseName, withExtension: descriptor.fileExtension) else {
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
