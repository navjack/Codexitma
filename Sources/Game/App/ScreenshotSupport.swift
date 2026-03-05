import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum ScreenshotSupport {
    private static let screenshotDirectoryOverrideEnvironmentKey = "CODEXITMA_SCREENSHOT_DIR"

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()

    static func makeScreenshotURL(prefix: String, label: String, fileExtension: String) throws -> URL {
        let base = try screenshotsDirectory()
        let timestamp = timestampFormatter.string(from: Date())
        let sanitizedLabel = sanitize(label)
        let ext = sanitize(fileExtension).lowercased()
        let filename = "\(sanitize(prefix))-\(timestamp)-\(sanitizedLabel).\(ext)"
        return base.appendingPathComponent(filename, isDirectory: false)
    }

    private static func screenshotsDirectory() throws -> URL {
        let manager = FileManager.default
        if let overridePath = ProcessInfo.processInfo.environment[screenshotDirectoryOverrideEnvironmentKey],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try manager.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            return overrideURL
        }

        let baseRoot = CodexitmaPaths.dataRoot(fileManager: manager)
        let screenshots = baseRoot
            .appendingPathComponent("Screenshots", isDirectory: true)
        try manager.createDirectory(at: screenshots, withIntermediateDirectories: true)
        return screenshots
    }

    static func sanitize(_ value: String) -> String {
        let lowered = value.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let scalars = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return collapsed.isEmpty ? "capture" : collapsed
    }

    static func defaultGameLabel(for state: GameState) -> String {
        switch state.mode {
        case .title:
            return "title-\(state.selectedAdventureID().rawValue)"
        case .characterCreation:
            return "creator-\(state.selectedHeroClass().rawValue)"
        case .ending:
            return "ending-\(state.currentAdventureID.rawValue)"
        default:
            return "\(state.currentAdventureID.rawValue)-\(state.player.currentMapID)-\(String(describing: state.mode))"
        }
    }
}

#if canImport(AppKit)
enum NativeScreenshotCapture {
    enum CaptureError: Error, CustomStringConvertible {
        case missingWindow
        case missingContentView
        case failedBitmapCapture
        case failedEncoding

        var description: String {
            switch self {
            case .missingWindow:
                return "No key window was available for screenshot capture."
            case .missingContentView:
                return "The active window has no content view to capture."
            case .failedBitmapCapture:
                return "Failed to cache the active framebuffer."
            case .failedEncoding:
                return "Failed to encode the screenshot as PNG."
            }
        }
    }

    @MainActor
    static func captureKeyWindow(label: String) throws -> URL {
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
            throw CaptureError.missingWindow
        }
        guard let contentView = window.contentView else {
            throw CaptureError.missingContentView
        }

        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CaptureError.failedBitmapCapture
        }
        contentView.cacheDisplay(in: bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.failedEncoding
        }

        let url = try ScreenshotSupport.makeScreenshotURL(prefix: "native", label: label, fileExtension: "png")
        try pngData.write(to: url, options: .atomic)
        return url
    }
}
#endif
