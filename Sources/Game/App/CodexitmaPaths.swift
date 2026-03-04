import Foundation

#if os(Windows)
import WinSDK
#endif

enum CodexitmaPaths {
    static func appSupportRoot(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Codexitma", isDirectory: true)
    }

    static func dataRoot(fileManager: FileManager = .default) -> URL {
        #if os(Windows)
        if let portable = preferredWindowsPortableRoot(fileManager: fileManager) {
            return portable
        }
        #endif
        return appSupportRoot(fileManager: fileManager)
    }

    #if os(Windows)
    private static func preferredWindowsPortableRoot(fileManager: FileManager) -> URL? {
        guard let executableDirectory = executableDirectoryURL(fileManager: fileManager) else {
            return nil
        }
        let root = executableDirectory.appendingPathComponent("CodexitmaData", isDirectory: true)
        return ensureWritableDirectory(root, fileManager: fileManager) ? root : nil
    }

    private static func executableDirectoryURL(fileManager: FileManager) -> URL? {
        var buffer = Array<WCHAR>(repeating: 0, count: 32768)
        let length = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        if length > 0 {
            let path = String(decoding: buffer.prefix(length), as: UTF16.self)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: false).deletingLastPathComponent()
            }
        }

        guard let executablePath = CommandLine.arguments.first, !executablePath.isEmpty else {
            return nil
        }
        let nsPath = executablePath as NSString
        let resolvedPath: String
        if nsPath.isAbsolutePath {
            resolvedPath = executablePath
        } else {
            resolvedPath = (fileManager.currentDirectoryPath as NSString).appendingPathComponent(executablePath)
        }
        return URL(fileURLWithPath: resolvedPath, isDirectory: false).deletingLastPathComponent()
    }

    private static func ensureWritableDirectory(_ directory: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent(".codexitma-write-\(UUID().uuidString)", isDirectory: false)
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try? fileManager.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
    #endif
}
