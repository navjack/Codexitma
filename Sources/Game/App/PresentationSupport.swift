#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

final class GraphicsPreferenceStore: @unchecked Sendable {
    static let shared = GraphicsPreferenceStore()

    private let themeKey = "codexitma.graphics.visualTheme"
    #if os(Windows)
    private let fileURL: URL
    #else
    private let defaults: UserDefaults
    #endif

    #if os(Windows)
    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let folder = CodexitmaPaths.dataRoot(fileManager: fileManager)
        self.fileURL = folder.appendingPathComponent("graphics_theme.json")
    }
    #else
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #endif

    func loadTheme() -> GraphicsVisualTheme {
        #if os(Windows)
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(GraphicsThemePreferencePayload.self, from: data),
              let theme = GraphicsVisualTheme(rawValue: payload.visualTheme) else {
            return .gemstone
        }
        return theme
        #else
        guard let rawValue = defaults.string(forKey: themeKey),
              let theme = GraphicsVisualTheme(rawValue: rawValue) else {
            return .gemstone
        }
        return theme
        #endif
    }

    func saveTheme(_ theme: GraphicsVisualTheme) {
        #if os(Windows)
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = GraphicsThemePreferencePayload(visualTheme: theme.rawValue)
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
        #else
        defaults.set(theme.rawValue, forKey: themeKey)
        #endif
    }
}

private struct GraphicsThemePreferencePayload: Codable {
    let visualTheme: String
}

private extension GameSoundCue {
    var notes: [(frequency: Double, duration: Double)] {
        switch self {
        case .introMusic:
            return [
                (329.6, 0.08),
                (392.0, 0.08),
                (523.3, 0.10),
                (659.3, 0.12),
                (523.3, 0.16),
            ]
        case .walk:
            return [
                (146.8, 0.03),
            ]
        case .attack:
            return [
                (220.0, 0.04),
                (110.0, 0.06),
            ]
        case .useItem:
            return [
                (523.3, 0.05),
                (659.3, 0.08),
            ]
        case .menuConfirm:
            return [
                (392.0, 0.04),
                (523.3, 0.06),
            ]
        }
    }
}

#if canImport(AVFoundation)
@MainActor
final class AppleIISoundEngine: GameSoundPlayback {
    static let shared = AppleIISoundEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var configured = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        configureIfNeeded()
    }

    func play(_ cue: GameSoundCue) {
        guard configureIfNeeded() else { return }
        player.stop()
        player.reset()

        for note in cue.notes {
            if let buffer = makeSquareWaveBuffer(frequency: note.frequency, duration: note.duration) {
                player.scheduleBuffer(buffer)
            }
        }

        if !player.isPlaying {
            player.play()
        }
    }

    @discardableResult
    private func configureIfNeeded() -> Bool {
        guard !configured else {
            if !engine.isRunning {
                try? engine.start()
            }
            return engine.isRunning
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.18
        try? engine.start()
        configured = engine.isRunning
        return configured
    }

    private func makeSquareWaveBuffer(frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(max(1, Int(format.sampleRate * duration)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = frameCount
        let sampleRate = format.sampleRate
        let amplitude: Float = 0.22

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let phase = sin(2.0 * .pi * frequency * time)
            channel[frame] = phase >= 0 ? amplitude : -amplitude
        }

        return buffer
    }
}
#endif
