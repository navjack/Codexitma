import Foundation

enum SaveError: Error {
    case notFound
    case corrupt
}

final class SaveRepository: @unchecked Sendable {
    let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = appSupport.appendingPathComponent("AshesOfMerrow", isDirectory: true)
        self.fileURL = folder.appendingPathComponent("savegame.json")
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func save(_ save: SaveGame) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(save)
        let tempURL = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        try data.write(to: tempURL, options: .atomic)
        _ = try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }

    func load() throws -> SaveGame {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SaveError.notFound
        }
        let data = try Data(contentsOf: fileURL)
        guard let save = try? JSONDecoder().decode(SaveGame.self, from: data) else {
            throw SaveError.corrupt
        }
        return save
    }
}
