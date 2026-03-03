import AppKit
import Foundation
import SwiftUI

enum LaunchMode: Equatable {
    case graphics
    case terminal

    static func parse(arguments: [String]) -> LaunchMode {
        if arguments.contains("--terminal") {
            return .terminal
        }
        return .graphics
    }
}

final class GameSessionController: ObservableObject {
    @Published private(set) var state: GameState

    private let engine: GameEngine

    init(content: GameContent, saveRepository: SaveRepository) {
        let engine = GameEngine(content: content, saveRepository: saveRepository)
        self.engine = engine
        self.state = engine.state
    }

    func send(_ command: ActionCommand) {
        engine.handle(command)
        state = engine.state
        if state.shouldQuit {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

@MainActor
enum GraphicsGameLauncher {
    private static var retainedDelegate: GraphicsAppDelegate?

    static func run(content: GameContent, saveRepository: SaveRepository) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let session = GameSessionController(content: content, saveRepository: saveRepository)
        let delegate = GraphicsAppDelegate(session: session)
        retainedDelegate = delegate
        app.delegate = delegate
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}

final class GraphicsAppDelegate: NSObject, NSApplicationDelegate {
    private let session: GameSessionController
    private var window: NSWindow?

    init(session: GameSessionController) {
        self.session = session
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma"
        window.backgroundColor = .black
        window.center()
        window.contentView = NSHostingView(rootView: GameRootView(session: session))
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct GameRootView: View {
    @ObservedObject var session: GameSessionController

    private let palette = UltimaPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            PixelStars(color: palette.accentBlue).ignoresSafeArea()
            PixelKeyCapture { session.send($0) }
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

            switch session.state.mode {
            case .title:
                titleView
            case .ending:
                endingView
            default:
                worldView
            }
        }
        .onMoveCommand(perform: handleMove)
    }

    private var titleView: some View {
        VStack(spacing: 16) {
            Spacer()
            PixelBanner(text: "CODEXITMA", color: palette.titleGold)
            Text("A LOW-RES APPLE II FANTASY")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text)
            Text("ASHES OF MERROW // ULTIMA-STYLED")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.accentBlue)

            HStack(spacing: 10) {
                menuButton("N: NEW") { session.send(.newGame) }
                menuButton("L: LOAD") { session.send(.load) }
                menuButton("X: QUIT") { session.send(.quit) }
            }

            VStack(spacing: 4) {
                Text("MOVE WITH ARROWS OR WASD")
                Text("E ACT   I USE ITEM   J HINT   K SAVE")
                Text("RUN WITH --TERMINAL FOR THE TEXT MODE")
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.85))
            Spacer()
        }
        .padding(28)
    }

    private var endingView: some View {
        VStack(spacing: 16) {
            Spacer()
            PixelBanner(text: "BEACON LIT", color: palette.lightGold)
            Text("THE VALLEY ENDURES.")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text)
            if let line = session.state.messages.last {
                Text(line.uppercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.accentBlue)
            }
            menuButton("X: EXIT") { session.send(.quit) }
            Spacer()
        }
        .padding(28)
    }

    private var worldView: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                PixelPanel(title: currentMapName.uppercased(), palette: palette) {
                    MapBoardView(state: session.state, palette: palette)
                }

                PixelPanel(title: "LOG", palette: palette) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(session.state.messages.suffix(5).enumerated()), id: \.offset) { _, line in
                            Text(line.uppercased())
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                PixelPanel(title: "STATUS", palette: palette) {
                    VStack(alignment: .leading, spacing: 5) {
                        stat("NAME", session.state.player.name.uppercased())
                        stat("HP", "\(session.state.player.health)/\(session.state.player.maxHealth)")
                        stat("ST", "\(session.state.player.stamina)/\(session.state.player.maxStamina)")
                        stat("LN", "\(session.state.player.lanternCharge)")
                        stat("GOAL", QuestSystem.objective(for: session.state.quests).uppercased())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                PixelPanel(title: "PACK", palette: palette) {
                    VStack(alignment: .leading, spacing: 4) {
                        if session.state.player.inventory.isEmpty {
                            Text("EMPTY")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text)
                        } else {
                            ForEach(Array(session.state.player.inventory.prefix(6).enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 5) {
                                    Rectangle()
                                        .fill(itemColor(item))
                                        .frame(width: 8, height: 8)
                                    Text(item.name.uppercased())
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundStyle(palette.text)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                PixelPanel(title: "INPUT", palette: palette) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            menuButton("I") {
                                session.send(.openInventory)
                                session.send(.confirm)
                            }
                            menuButton("J") { session.send(.help) }
                            menuButton("E") { session.send(.interact) }
                        }
                        HStack(spacing: 8) {
                            menuButton("K") { session.send(.save) }
                            menuButton("L") { session.send(.load) }
                            menuButton("X") { session.send(.quit) }
                        }
                    }
                }
            }
            .frame(width: 250)
        }
        .padding(18)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(palette.lightGold)
                .overlay(Rectangle().stroke(palette.titleGold, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            session.send(.move(.up))
        case .down:
            session.send(.move(.down))
        case .left:
            session.send(.move(.left))
        case .right:
            session.send(.move(.right))
        @unknown default:
            break
        }
    }

    private var currentMapName: String {
        session.state.world.maps[session.state.player.currentMapID]?.name ?? "UNKNOWN"
    }

    private func itemColor(_ item: Item) -> Color {
        switch item.kind {
        case .consumable:
            return palette.accentGreen
        case .key:
            return palette.lightGold
        case .quest:
            return palette.accentBlue
        case .upgrade:
            return palette.accentViolet
        }
    }
}

private struct MapBoardView: View {
    let state: GameState
    let palette: UltimaPalette

    private let cell: CGFloat = 16

    var body: some View {
        let map = state.world.maps[state.player.currentMapID]
        VStack(spacing: 0) {
            ForEach(Array((map?.lines ?? []).enumerated()), id: \.offset) { y, line in
                HStack(spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { x, raw in
                        LowResTileView(
                            tile: TileFactory.tile(for: resolved(raw)),
                            occupant: occupant(at: Position(x: x, y: y)),
                            palette: palette
                        )
                        .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .scaleEffect(2, anchor: .topLeading)
        .frame(
            width: CGFloat(map?.lines.first?.count ?? 0) * cell * 2,
            height: CGFloat(map?.lines.count ?? 0) * cell * 2,
            alignment: .topLeading
        )
        .clipped()
    }

    private func resolved(_ raw: Character) -> Character {
        if raw == "+", state.quests.has(.barrowUnlocked) {
            return "/"
        }
        return raw
    }

    private func occupant(at position: Position) -> MapOccupant {
        if state.player.position == position {
            return .player
        }
        if state.player.currentMapID == "merrow_village", position == Position(x: 6, y: 5) {
            return .npc
        }
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return enemy.ai == .boss ? .boss : .enemy
        }
        return .none
    }
}

private enum MapOccupant {
    case none
    case player
    case npc
    case enemy
    case boss
}

private struct LowResTileView: View {
    let tile: Tile
    let occupant: MapOccupant
    let palette: UltimaPalette

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(tileColor)
                tileMark(size: size)
                sprite(size: size)
            }
            .overlay(Rectangle().stroke(palette.background, lineWidth: 1))
        }
    }

    private var tileColor: Color {
        switch tile.type {
        case .floor: return palette.ground
        case .wall: return palette.stone
        case .water: return palette.accentBlue
        case .brush: return palette.accentGreen
        case .doorLocked: return palette.titleGold
        case .doorOpen: return palette.lightGold
        case .shrine: return palette.accentViolet
        case .stairs: return palette.earth
        case .beacon: return palette.lightGold
        }
    }

    @ViewBuilder
    private func tileMark(size: CGFloat) -> some View {
        switch tile.type {
        case .water:
            VStack(spacing: 0) {
                Rectangle().fill(palette.text).frame(width: size, height: max(1, size * 0.14))
                Spacer()
                Rectangle().fill(palette.text).frame(width: size * 0.6, height: max(1, size * 0.14))
            }
        case .brush:
            HStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(palette.text).frame(width: max(1, size * 0.12), height: size * 0.5)
                Rectangle().fill(palette.text).frame(width: max(1, size * 0.12), height: size * 0.7)
            }
        case .doorLocked, .doorOpen:
            Rectangle()
                .fill(palette.background.opacity(0.4))
                .frame(width: size * 0.4, height: size * 0.7)
        case .shrine, .beacon:
            Rectangle()
                .fill(palette.text)
                .frame(width: size * 0.24, height: size * 0.24)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sprite(size: CGFloat) -> some View {
        switch occupant {
        case .none:
            EmptyView()
        case .player:
            PixelSprite(color: palette.text, pattern: [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ])
            .frame(width: size * 0.75, height: size * 0.75)
        case .npc:
            PixelSprite(color: palette.lightGold, pattern: [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ])
            .frame(width: size * 0.75, height: size * 0.75)
        case .enemy:
            PixelSprite(color: palette.titleGold, pattern: [
                [1,0,1],
                [0,1,0],
                [1,1,1]
            ])
            .frame(width: size * 0.8, height: size * 0.8)
        case .boss:
            PixelSprite(color: palette.accentViolet, pattern: [
                [1,0,1],
                [1,1,1],
                [1,0,1]
            ])
            .frame(width: size * 0.85, height: size * 0.85)
        }
    }
}

private struct PixelSprite: View {
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
    }
}

private struct PixelPanel<Content: View>: View {
    let title: String
    let palette: UltimaPalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(" \(title) ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.background)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(palette.lightGold)

            content()
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.panel)
        }
        .overlay(Rectangle().stroke(palette.lightGold, lineWidth: 2))
        .background(palette.panel)
    }
}

private struct PixelBanner: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .black, design: .monospaced))
            .foregroundStyle(color)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.black)
            .overlay(Rectangle().stroke(color, lineWidth: 3))
    }
}

private struct PixelStars: View {
    let color: Color

    private let points: [CGPoint] = [
        CGPoint(x: 0.08, y: 0.10),
        CGPoint(x: 0.18, y: 0.15),
        CGPoint(x: 0.35, y: 0.09),
        CGPoint(x: 0.62, y: 0.12),
        CGPoint(x: 0.80, y: 0.17),
        CGPoint(x: 0.91, y: 0.08),
        CGPoint(x: 0.12, y: 0.82),
        CGPoint(x: 0.52, y: 0.76),
        CGPoint(x: 0.86, y: 0.71)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Rectangle()
                    .fill(color.opacity(0.35))
                    .frame(width: 3, height: 3)
                    .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
            }
        }
    }
}

private struct PixelKeyCapture: NSViewRepresentable {
    let onCommand: (ActionCommand) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCommand = onCommand
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCommand = onCommand
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureView: NSView {
    var onCommand: ((ActionCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let command = parse(event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
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
        case "j", "h": return .help
        case "k": return .save
        case "l": return .load
        case "n": return .newGame
        case "x", "q": return .quit
        default: return nil
        }
    }
}

private struct UltimaPalette {
    let background = Color.black
    let panel = Color(red: 0.05, green: 0.05, blue: 0.03)
    let text = Color(red: 0.93, green: 0.91, blue: 0.83)
    let label = Color(red: 0.93, green: 0.74, blue: 0.27)
    let lightGold = Color(red: 0.94, green: 0.83, blue: 0.34)
    let titleGold = Color(red: 0.95, green: 0.58, blue: 0.12)
    let accentBlue = Color(red: 0.31, green: 0.57, blue: 0.86)
    let accentGreen = Color(red: 0.24, green: 0.63, blue: 0.24)
    let accentViolet = Color(red: 0.44, green: 0.28, blue: 0.64)
    let stone = Color(red: 0.36, green: 0.36, blue: 0.40)
    let ground = Color(red: 0.34, green: 0.24, blue: 0.14)
    let earth = Color(red: 0.46, green: 0.35, blue: 0.22)
}
