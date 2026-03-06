import Foundation

enum SaveError: Error {
    case notFound
    case corrupt
}

final class SaveRepository: @unchecked Sendable {
    let fileURL: URL
    let legacyFileURLs: [URL]

    init(fileManager: FileManager = .default) {
        let dataRoot = CodexitmaPaths.dataRoot(fileManager: fileManager)
        self.fileURL = dataRoot.appendingPathComponent("savegame.json")

        let appSupportRoot = CodexitmaPaths.appSupportRoot(fileManager: fileManager)
        let legacyCodexitma = appSupportRoot.appendingPathComponent("savegame.json")
        let legacyAshes = appSupportRoot
            .deletingLastPathComponent()
            .appendingPathComponent("AshesOfMerrow", isDirectory: true)
            .appendingPathComponent("savegame.json")

        var legacy: [URL] = []
        if legacyCodexitma != self.fileURL {
            legacy.append(legacyCodexitma)
        }
        if legacyAshes != self.fileURL {
            legacy.append(legacyAshes)
        }
        self.legacyFileURLs = legacy
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.legacyFileURLs = []
    }

    func save(_ save: SaveGame) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(save)
        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }

    func load() throws -> SaveGame {
        let sourceURL: URL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            sourceURL = fileURL
        } else if let legacyURL = legacyFileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            sourceURL = legacyURL
        } else {
            throw SaveError.notFound
        }
        let data = try Data(contentsOf: sourceURL)
        guard let save = try? JSONDecoder().decode(SaveGame.self, from: data) else {
            throw SaveError.corrupt
        }
        return save
    }
}
