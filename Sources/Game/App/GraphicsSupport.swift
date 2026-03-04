#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

struct PixelSprite: View {
    let color: Color
    let pattern: [[Int]]

    var body: some View {
        GeometryReader { proxy in
            let rows = pattern.count
            let cols = pattern.first?.count ?? 1
            let pixel = min(proxy.size.width / CGFloat(max(cols, 1)),
                            proxy.size.height / CGFloat(max(rows, 1)))
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            Rectangle()
                                .fill(pattern[row][col] == 1 ? color : .clear)
                                .frame(width: pixel, height: pixel)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .drawingGroup(opaque: false)
    }
}

struct PixelPanel<Content: View>: View {
    let title: String
    let palette: UltimaPalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.titleGold)
                    .frame(height: 22)
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(palette.lightGold.opacity(0.35))
                        .frame(width: 6, height: 22)
                    Text(" \(title) ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.background)
                }
            }

            content()
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.panel)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(palette.titleGold, lineWidth: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .inset(by: 4)
                .stroke(palette.lightGold.opacity(0.55), lineWidth: 1)
        )
        .background(palette.panel)
    }
}

struct PixelBanner: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .black, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    color
                    HStack(spacing: 5) {
                        ForEach(0..<6, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(width: 3)
                        }
                    }
                }
            )
            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
            .overlay(Rectangle().inset(by: 4).stroke(color.opacity(0.35), lineWidth: 2))
    }
}

struct PixelStars: View {
    let color: Color

    private let points: [CGPoint] = [
        CGPoint(x: 0.07, y: 0.09),
        CGPoint(x: 0.16, y: 0.18),
        CGPoint(x: 0.34, y: 0.11),
        CGPoint(x: 0.61, y: 0.14),
        CGPoint(x: 0.81, y: 0.16),
        CGPoint(x: 0.92, y: 0.08),
        CGPoint(x: 0.11, y: 0.81),
        CGPoint(x: 0.49, y: 0.75),
        CGPoint(x: 0.71, y: 0.83),
        CGPoint(x: 0.87, y: 0.68)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                let size: CGFloat = index.isMultiple(of: 3) ? 4 : 2
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? color.opacity(0.32) : Color.white.opacity(0.18))
                    .frame(width: size, height: size)
                    .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
            }
        }
    }
}

struct PixelKeyCapture: NSViewRepresentable {
    let onCommand: (ActionCommand) -> Void
    let onThemeToggle: () -> Void
    let onEditorRequest: () -> Void
    let onScreenshotRequest: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCommand = onCommand
        view.onThemeToggle = onThemeToggle
        view.onEditorRequest = onEditorRequest
        view.onScreenshotRequest = onScreenshotRequest
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCommand = onCommand
        nsView.onThemeToggle = onThemeToggle
        nsView.onEditorRequest = onEditorRequest
        nsView.onScreenshotRequest = onScreenshotRequest
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCaptureView: NSView {
    var onCommand: ((ActionCommand) -> Void)?
    var onThemeToggle: (() -> Void)?
    var onEditorRequest: (() -> Void)?
    var onScreenshotRequest: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isThemeToggle(event) {
            onThemeToggle?()
        } else if isEditorRequest(event) {
            onEditorRequest?()
        } else if isScreenshotRequest(event) {
            onScreenshotRequest?()
        } else if let command = parse(event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    private func isThemeToggle(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let char = chars.first else {
            return false
        }
        return char == "t"
    }

    private func isEditorRequest(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let char = chars.first else {
            return false
        }
        return char == "m"
    }

    private func isScreenshotRequest(_ event: NSEvent) -> Bool {
        event.keyCode == 111 // F12
    }

    private func parse(_ event: NSEvent) -> ActionCommand? {
        switch event.keyCode {
        case 123: return .move(.left)
        case 124: return .move(.right)
        case 125: return .move(.down)
        case 126: return .move(.up)
        default: break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let char = chars.first else {
            return nil
        }

        switch char {
        case "w": return .move(.up)
        case "s": return .move(.down)
        case "a": return .move(.left)
        case "d": return .move(.right)
        case "e", " ": return .interact
        case "i": return .openInventory
        case "r": return .dropInventoryItem
        case "j", "h": return .help
        case "k": return .save
        case "l": return .load
        case "n": return .newGame
        case "q": return .cancel
        case "x": return .quit
        default: return nil
        }
    }
}

struct UltimaPalette {
    let background = Color.black
    let panel = Color(red: 0.03, green: 0.03, blue: 0.02)
    let text = Color(red: 0.96, green: 0.94, blue: 0.86)
    let label = Color(red: 0.96, green: 0.78, blue: 0.20)
    let lightGold = Color(red: 0.98, green: 0.86, blue: 0.26)
    let titleGold = Color(red: 0.95, green: 0.52, blue: 0.05)
    let accentBlue = Color(red: 0.16, green: 0.61, blue: 0.92)
    let accentGreen = Color(red: 0.24, green: 0.76, blue: 0.15)
    let accentViolet = Color(red: 0.73, green: 0.29, blue: 0.86)
    let stone = Color(red: 0.39, green: 0.39, blue: 0.42)
    let ground = Color(red: 0.26, green: 0.18, blue: 0.08)
    let earth = Color(red: 0.52, green: 0.34, blue: 0.08)
}

enum ChamberPattern {
    case brick
    case speckle
    case weave
    case hash
    case mire
    case circuit
}

struct RegionTheme {
    let floor: Color
    let wall: Color
    let water: Color
    let brush: Color
    let doorLocked: Color
    let doorOpen: Color
    let shrine: Color
    let stairs: Color
    let beacon: Color
    let roomBorder: Color
    let roomHighlight: Color
    let roomShadow: Color
    let pattern: ChamberPattern
}
#endif
