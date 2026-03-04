import Foundation

enum GraphicsFloorPatternName: String, Codable {
    case brick
    case speckle
    case weave
    case hash
    case mire
    case circuit
}

struct GraphicsRGBColor: Codable, Equatable {
    let r: Int
    let g: Int
    let b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = Self.clamp(r)
        self.g = Self.clamp(g)
        self.b = Self.clamp(b)
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let hex = try? container.decode(String.self),
           let color = Self.parseHex(hex) {
            self = color
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let r = try container.decode(Int.self, forKey: .r)
        let g = try container.decode(Int.self, forKey: .g)
        let b = try container.decode(Int.self, forKey: .b)
        self.init(r: r, g: g, b: b)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(r, forKey: .r)
        try container.encode(g, forKey: .g)
        try container.encode(b, forKey: .b)
    }

    private enum CodingKeys: String, CodingKey {
        case r
        case g
        case b
    }

    private static func parseHex(_ raw: String) -> GraphicsRGBColor? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let intValue = Int(value, radix: 16) else {
            return nil
        }
        let r = (intValue >> 16) & 0xFF
        let g = (intValue >> 8) & 0xFF
        let b = intValue & 0xFF
        return GraphicsRGBColor(r: r, g: g, b: b)
    }

    private static func clamp(_ value: Int) -> Int {
        max(0, min(255, value))
    }
}

struct GraphicsPixelPattern: Codable, Equatable {
    let rows: [[Int]]

    init(rows: [[Int]]) {
        self.rows = rows
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let stringRows = try? container.decode([String].self) {
            self.rows = Self.convert(stringRows: stringRows)
            return
        }
        let container = try decoder.singleValueContainer()
        let matrix = try container.decode([[Int]].self)
        self.rows = matrix.map { row in
            row.map { $0 == 0 ? 0 : 1 }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rows)
    }

    private static func convert(stringRows: [String]) -> [[Int]] {
        let parsed = stringRows.map { row in
            row.map { $0 == "1" ? 1 : 0 }
        }
        return parsed.isEmpty ? [[1]] : parsed
    }
}

struct GraphicsMapThemeOverride: Codable, Equatable {
    var pattern: GraphicsFloorPatternName?
    var floor: GraphicsRGBColor?
    var wall: GraphicsRGBColor?
    var water: GraphicsRGBColor?
    var brush: GraphicsRGBColor?
    var doorLocked: GraphicsRGBColor?
    var doorOpen: GraphicsRGBColor?
    var shrine: GraphicsRGBColor?
    var stairs: GraphicsRGBColor?
    var beacon: GraphicsRGBColor?
    var roomBorder: GraphicsRGBColor?
    var roomHighlight: GraphicsRGBColor?
    var roomShadow: GraphicsRGBColor?

    func merged(with overlay: GraphicsMapThemeOverride) -> GraphicsMapThemeOverride {
        GraphicsMapThemeOverride(
            pattern: overlay.pattern ?? pattern,
            floor: overlay.floor ?? floor,
            wall: overlay.wall ?? wall,
            water: overlay.water ?? water,
            brush: overlay.brush ?? brush,
            doorLocked: overlay.doorLocked ?? doorLocked,
            doorOpen: overlay.doorOpen ?? doorOpen,
            shrine: overlay.shrine ?? shrine,
            stairs: overlay.stairs ?? stairs,
            beacon: overlay.beacon ?? beacon,
            roomBorder: overlay.roomBorder ?? roomBorder,
            roomHighlight: overlay.roomHighlight ?? roomHighlight,
            roomShadow: overlay.roomShadow ?? roomShadow
        )
    }
}

struct GraphicsSpriteOverride: Codable, Equatable {
    var pattern: GraphicsPixelPattern?
    var color: GraphicsRGBColor?

    func merged(with overlay: GraphicsSpriteOverride) -> GraphicsSpriteOverride {
        GraphicsSpriteOverride(
            pattern: overlay.pattern ?? pattern,
            color: overlay.color ?? color
        )
    }
}

struct GraphicsAssetPack: Codable, Equatable {
    var mapThemes: [String: GraphicsMapThemeOverride]
    var npcSprites: [String: GraphicsSpriteOverride]
    var enemySprites: [String: GraphicsSpriteOverride]
    var featureSprites: [String: GraphicsSpriteOverride]
    var occupantSprites: [String: GraphicsSpriteOverride]

    init(
        mapThemes: [String: GraphicsMapThemeOverride] = [:],
        npcSprites: [String: GraphicsSpriteOverride] = [:],
        enemySprites: [String: GraphicsSpriteOverride] = [:],
        featureSprites: [String: GraphicsSpriteOverride] = [:],
        occupantSprites: [String: GraphicsSpriteOverride] = [:]
    ) {
        self.mapThemes = mapThemes
        self.npcSprites = npcSprites
        self.enemySprites = enemySprites
        self.featureSprites = featureSprites
        self.occupantSprites = occupantSprites
    }

    static let empty = GraphicsAssetPack()

    func merged(with overlay: GraphicsAssetPack) -> GraphicsAssetPack {
        GraphicsAssetPack(
            mapThemes: Self.mergeMapThemeDict(base: mapThemes, overlay: overlay.mapThemes),
            npcSprites: Self.mergeSpriteDict(base: npcSprites, overlay: overlay.npcSprites),
            enemySprites: Self.mergeSpriteDict(base: enemySprites, overlay: overlay.enemySprites),
            featureSprites: Self.mergeSpriteDict(base: featureSprites, overlay: overlay.featureSprites),
            occupantSprites: Self.mergeSpriteDict(base: occupantSprites, overlay: overlay.occupantSprites)
        )
    }

    private static func mergeSpriteDict(
        base: [String: GraphicsSpriteOverride],
        overlay: [String: GraphicsSpriteOverride]
    ) -> [String: GraphicsSpriteOverride] {
        var merged = base
        for (key, value) in overlay {
            if let existing = merged[key] {
                merged[key] = existing.merged(with: value)
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    private static func mergeMapThemeDict(
        base: [String: GraphicsMapThemeOverride],
        overlay: [String: GraphicsMapThemeOverride]
    ) -> [String: GraphicsMapThemeOverride] {
        var merged = base
        for (key, value) in overlay {
            if let existing = merged[key] {
                merged[key] = existing.merged(with: value)
            } else {
                merged[key] = value
            }
        }
        return merged
    }
}

enum GraphicsAssetCatalog {
    static let shared = load()

    static func load(
        bundle: Bundle = GameResourceBundle.current,
        externalURL: URL? = nil
    ) -> GraphicsAssetPack {
        let base = decodePack(from: bundle.url(forResource: "graphics_assets", withExtension: "json")) ?? .empty
        let overlayURL = externalURL ?? defaultExternalURL()
        guard let overlayURL else {
            return base
        }

        let overlay = decodePack(from: overlayURL) ?? .empty
        return base.merged(with: overlay)
    }

    static func mapTheme(for mapID: String) -> GraphicsMapThemeOverride? {
        shared.mapThemes[mapID]
    }

    static func npcSprite(for id: String) -> GraphicsSpriteOverride? {
        sprite(from: shared.npcSprites, id: id)
    }

    static func enemySprite(for id: String) -> GraphicsSpriteOverride? {
        sprite(from: shared.enemySprites, id: id)
    }

    static func featureSprite(for id: String) -> GraphicsSpriteOverride? {
        shared.featureSprites[id]
    }

    static func occupantSprite(for id: String) -> GraphicsSpriteOverride? {
        shared.occupantSprites[id]
    }

    static func floorPattern(for mapID: String) -> GraphicsFloorPatternName? {
        mapTheme(for: mapID)?.pattern
    }

    private static func decodePack(from url: URL?) -> GraphicsAssetPack? {
        guard let url else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GraphicsAssetPack.self, from: data)
    }

    private static func defaultExternalURL() -> URL? {
        let manager = FileManager.default
        let dataRoot = CodexitmaPaths.dataRoot(fileManager: manager)
        let appSupportRoot = CodexitmaPaths.appSupportRoot(fileManager: manager)

        let candidates = [
            dataRoot
                .appendingPathComponent("graphics_assets.json", isDirectory: false),
            dataRoot
                .appendingPathComponent("Graphics", isDirectory: true)
                .appendingPathComponent("graphics_assets.json", isDirectory: false),
            appSupportRoot
                .appendingPathComponent("graphics_assets.json", isDirectory: false),
            appSupportRoot
                .appendingPathComponent("Graphics", isDirectory: true)
                .appendingPathComponent("graphics_assets.json", isDirectory: false),
        ]

        for candidate in candidates where manager.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private static func sprite(from table: [String: GraphicsSpriteOverride], id: String) -> GraphicsSpriteOverride? {
        if let exact = table[id] {
            return exact
        }

        let wildcardMatches = table
            .filter { $0.key.hasSuffix("*") && id.hasPrefix(String($0.key.dropLast())) }
            .sorted { $0.key.count > $1.key.count }

        return wildcardMatches.first?.value
    }
}
