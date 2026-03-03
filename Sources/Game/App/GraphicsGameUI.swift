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
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codexitma"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 1100, height: 700)
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
            case .characterCreation:
                creatorView
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
            Text("ASHES OF MERROW // CLASSES, TRAITS, AND LOW-RES LEGENDS")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.accentBlue)

            HStack(spacing: 10) {
                menuButton("N: CREATE") { session.send(.newGame) }
                menuButton("L: LOAD") { session.send(.load) }
                menuButton("X: QUIT") { session.send(.quit) }
            }

            VStack(spacing: 4) {
                Text("GEMSTONE-STYLE CHAMBERS. CREATE A HERO BEFORE YOU ENTER THE VALLEY")
                Text("ARROWS/WASD STEP ROOM TO ROOM")
                Text("E TALK OR USE   I OPEN PACK")
                Text("J SHOW GOAL   K SAVE   L LOAD   X QUIT")
                Text("Q BACKS OUT OF MENUS   --BRIDGE / --SCRIPT FOR HEADLESS CONTROL")
            }
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.text.opacity(0.85))
            Spacer()
        }
        .padding(28)
    }

    private var creatorView: some View {
        let heroClass = session.state.selectedHeroClass()
        let template = heroTemplate(for: heroClass)

        return VStack(spacing: 16) {
            Spacer()
            PixelBanner(text: template.heroClass.displayName.uppercased(), color: palette.titleGold)
            Text(template.title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.lightGold)
            Text(template.summary.uppercased())
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                menuButton("A / LEFT") { session.send(.move(.left)) }
                menuButton("D / RIGHT") { session.send(.move(.right)) }
            }
            .frame(width: 320)

            PixelPanel(title: "TRAITS", palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TraitStat.allCases, id: \.self) { stat in
                        Text("\(stat.shortLabel) \(template.traits.value(for: stat))  \(stat.displayName.uppercased())")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text)
                    }
                }
                .frame(width: 300, alignment: .leading)
            }

            PixelPanel(title: "SKILLS", palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(template.skills, id: \.self) { skill in
                        Text("\(skill.displayName.uppercased()): \(skill.summary.uppercased())")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 420, alignment: .leading)
            }

            PixelPanel(title: "START LOADOUT", palette: palette) {
                VStack(alignment: .leading, spacing: 4) {
                    equipmentRow("WPN", template.startingEquipment.weapon.flatMap { itemTable[$0]?.name.uppercased() } ?? "NONE")
                    equipmentRow("ARM", template.startingEquipment.armor.flatMap { itemTable[$0]?.name.uppercased() } ?? "NONE")
                    equipmentRow("CHM", template.startingEquipment.charm.flatMap { itemTable[$0]?.name.uppercased() } ?? "NONE")
                    Text("PACK \(template.startingInventory.compactMap { itemTable[$0]?.name.uppercased() }.joined(separator: ", "))")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 420, alignment: .leading)
            }

            HStack(spacing: 10) {
                menuButton("E: BEGIN") { session.send(.confirm) }
                menuButton("Q: BACK") { session.send(.cancel) }
            }
            .frame(width: 320)
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
        let sidebarPanelWidth: CGFloat = 192

        return ScrollView([.vertical, .horizontal], showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    PixelPanel(title: "\(currentMapName.uppercased()) CHAMBER", palette: palette) {
                        MapBoardView(state: session.state, palette: palette)
                    }

                    PixelPanel(title: "LOG", palette: palette) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(session.state.messages.suffix(4).enumerated()), id: \.offset) { _, line in
                                Text(line.uppercased())
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(palette.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 620, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        statusPanel
                            .frame(width: sidebarPanelWidth)
                        packPanel
                            .frame(width: sidebarPanelWidth)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        paperDollPanel
                            .frame(width: sidebarPanelWidth)
                        inputPanel
                            .frame(width: sidebarPanelWidth)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        legendPanel
                            .frame(width: sidebarPanelWidth)
                        traitsPanel
                            .frame(width: sidebarPanelWidth)
                    }
                }
                .frame(width: (sidebarPanelWidth * 2) + 10, alignment: .leading)
            }
            .frame(minWidth: 1048, alignment: .topLeading)
            .padding(18)
        }
    }

    private var statusPanel: some View {
        PixelPanel(title: "STATUS", palette: palette) {
            VStack(alignment: .leading, spacing: 5) {
                stat("NAME", session.state.player.name.uppercased())
                stat("CLASS", session.state.player.heroClass.displayName.uppercased())
                stat("HP", "\(session.state.player.health)/\(session.state.player.maxHealth)")
                stat("ST", "\(session.state.player.stamina)/\(session.state.player.maxStamina)")
                stat("ATK", "\(session.state.player.effectiveAttack())")
                stat("DEF", "\(session.state.player.effectiveDefense())")
                stat("LN", "\(session.state.player.effectiveLanternCapacity())")
                stat("BAG", "\(session.state.player.inventory.count)/\(session.state.player.inventoryCapacity())")
                stat("GOAL", QuestSystem.objective(for: session.state.quests).uppercased())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packPanel: some View {
        PixelPanel(title: "PACK", palette: palette) {
            VStack(alignment: .leading, spacing: 4) {
                if session.state.player.inventory.isEmpty {
                    Text("EMPTY")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text)
                } else {
                    ForEach(Array(session.state.player.inventory.prefix(5).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(itemColor(item))
                                .frame(width: 8, height: 8)
                            Text(item.name.uppercased())
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paperDollPanel: some View {
        PixelPanel(title: "PAPER DOLL", palette: palette) {
            VStack(alignment: .leading, spacing: 8) {
                PixelSprite(color: palette.text, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [1,1,1],
                    [1,0,1]
                ])
                .frame(width: 44, height: 56)

                equipmentRow("WPN", session.state.player.equippedName(for: .weapon).uppercased())
                equipmentRow("ARM", session.state.player.equippedName(for: .armor).uppercased())
                equipmentRow("CHM", session.state.player.equippedName(for: .charm).uppercased())
            }
        }
    }

    private var inputPanel: some View {
        PixelPanel(title: "INPUT", palette: palette) {
            VStack(alignment: .leading, spacing: 5) {
                Text("ARROWS/WASD MOVE")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text("E ACT   I PACK   Q BACK")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text("J GOAL  K SAVE  L LOAD")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text("X QUIT")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        menuButton("I") { session.send(.openInventory) }
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
    }

    private var legendPanel: some View {
        PixelPanel(title: "LEGEND", palette: palette) {
            VStack(alignment: .leading, spacing: 4) {
                legendRow(color: palette.text, label: "PLAYER")
                legendRow(color: palette.lightGold, label: "NPC / TREASURE")
                legendRow(color: palette.titleGold, label: "HOSTILE")
                legendRow(color: palette.accentViolet, label: "RUNE / BOSS")
                legendRow(color: palette.accentBlue, label: "WATER / SIGNAL")
                legendRow(color: palette.accentGreen, label: "BRUSH / FIELD")
            }
        }
    }

    private var traitsPanel: some View {
        PixelPanel(title: "TRAITS", palette: palette) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.state.player.traitSummaryLine())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(session.state.player.traitSummaryLineSecondary())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
            }
        }
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

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay(Rectangle().stroke(palette.background, lineWidth: 1))
            Text(label)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
        }
    }

    private func equipmentRow(_ slot: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(slot)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.label)
                .frame(width: 26, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text)
                .lineLimit(1)
        }
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
        case .equipment:
            return palette.titleGold
        }
    }
}

private struct MapBoardView: View {
    let state: GameState
    let palette: UltimaPalette

    private let cell: CGFloat = 14
    private let boardScale: CGFloat = 2

    var body: some View {
        let map = state.world.maps[state.player.currentMapID]
        let theme = regionTheme
        let boardWidth = CGFloat(map?.lines.first?.count ?? 0) * cell
        let boardHeight = CGFloat(map?.lines.count ?? 0) * cell

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(theme.roomShadow)
                .offset(x: 3, y: 3)

            VStack(spacing: 0) {
                ForEach(Array((map?.lines ?? []).enumerated()), id: \.offset) { y, line in
                    HStack(spacing: 0) {
                        ForEach(Array(line.enumerated()), id: \.offset) { x, raw in
                            LowResTileView(
                                tile: TileFactory.tile(for: resolved(raw)),
                                occupant: occupant(at: Position(x: x, y: y)),
                                feature: feature(at: Position(x: x, y: y)),
                                palette: palette,
                                regionTheme: theme
                            )
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .padding(4)
            .background(Color.black)
            .overlay(
                Rectangle()
                    .stroke(theme.roomHighlight, lineWidth: 2)
                    .padding(3)
            )
            .overlay(
                Rectangle()
                    .stroke(theme.roomBorder, lineWidth: 4)
            )
        }
        .scaleEffect(boardScale, anchor: .topLeading)
        .frame(
            width: (boardWidth + 8) * boardScale,
            height: (boardHeight + 8) * boardScale,
            alignment: .topLeading
        )
        .clipped()
        .drawingGroup(opaque: false)
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
        if let npc = state.world.npcs.first(where: { $0.mapID == state.player.currentMapID && $0.position == position }) {
            return .npc(npc.id)
        }
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return enemy.ai == .boss ? .boss(enemy.id) : .enemy(enemy.id)
        }
        return .none
    }

    private func feature(at position: Position) -> MapFeature {
        guard let interactable = state.world.maps[state.player.currentMapID]?.interactables.first(where: { $0.position == position }) else {
            return .none
        }
        switch interactable.kind {
        case .chest:
            return state.world.openedInteractables.contains(interactable.id) ? .none : .chest
        case .bed:
            return .bed
        case .plate:
            return state.world.openedInteractables.contains(interactable.id) ? .plateDown : .plateUp
        case .switchRune:
            return state.world.openedInteractables.contains("spire_mirrors_aligned") ? .switchLit : .switchIdle
        case .shrine:
            return .shrine
        case .beacon:
            return .beacon
        case .gate:
            return .gate
        case .npc:
            return .none
        }
    }

    private var regionTheme: RegionTheme {
        switch state.player.currentMapID {
        case "merrow_village":
            return RegionTheme(
                floor: Color(red: 0.18, green: 0.11, blue: 0.08),
                wall: Color(red: 0.46, green: 0.23, blue: 0.12),
                water: palette.accentBlue,
                brush: Color(red: 0.27, green: 0.58, blue: 0.17),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: palette.earth,
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.95, green: 0.56, blue: 0.07),
                roomHighlight: palette.lightGold,
                roomShadow: Color.black.opacity(0.55),
                pattern: .brick
            )
        case "south_fields":
            return RegionTheme(
                floor: Color(red: 0.31, green: 0.18, blue: 0.06),
                wall: Color(red: 0.44, green: 0.35, blue: 0.11),
                water: palette.accentBlue,
                brush: Color(red: 0.32, green: 0.74, blue: 0.17),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.56, green: 0.40, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.90, green: 0.64, blue: 0.09),
                roomHighlight: Color(red: 0.98, green: 0.84, blue: 0.37),
                roomShadow: Color.black.opacity(0.55),
                pattern: .speckle
            )
        case "sunken_orchard":
            return RegionTheme(
                floor: Color(red: 0.21, green: 0.15, blue: 0.05),
                wall: Color(red: 0.36, green: 0.41, blue: 0.12),
                water: Color(red: 0.18, green: 0.46, blue: 0.75),
                brush: Color(red: 0.22, green: 0.58, blue: 0.13),
                doorLocked: Color(red: 0.78, green: 0.56, blue: 0.12),
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.44, green: 0.32, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.29, green: 0.74, blue: 0.24),
                roomHighlight: Color(red: 0.78, green: 0.92, blue: 0.36),
                roomShadow: Color.black.opacity(0.55),
                pattern: .weave
            )
        case "hollow_barrows":
            return RegionTheme(
                floor: Color(red: 0.14, green: 0.10, blue: 0.10),
                wall: Color(red: 0.50, green: 0.48, blue: 0.44),
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: Color(red: 0.78, green: 0.49, blue: 0.15),
                doorOpen: palette.lightGold,
                shrine: Color(red: 0.58, green: 0.38, blue: 0.80),
                stairs: Color(red: 0.48, green: 0.34, blue: 0.22),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.85, green: 0.85, blue: 0.78),
                roomHighlight: Color(red: 0.98, green: 0.96, blue: 0.86),
                roomShadow: Color.black.opacity(0.60),
                pattern: .hash
            )
        case "black_fen":
            return RegionTheme(
                floor: Color(red: 0.09, green: 0.14, blue: 0.08),
                wall: Color(red: 0.27, green: 0.36, blue: 0.16),
                water: Color(red: 0.17, green: 0.43, blue: 0.60),
                brush: Color(red: 0.33, green: 0.47, blue: 0.08),
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.31, green: 0.25, blue: 0.14),
                beacon: palette.lightGold,
                roomBorder: Color(red: 0.33, green: 0.68, blue: 0.22),
                roomHighlight: Color(red: 0.73, green: 0.88, blue: 0.31),
                roomShadow: Color.black.opacity(0.62),
                pattern: .mire
            )
        case "beacon_spire":
            return RegionTheme(
                floor: Color(red: 0.10, green: 0.10, blue: 0.18),
                wall: Color(red: 0.43, green: 0.43, blue: 0.58),
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: Color(red: 0.42, green: 0.30, blue: 0.15),
                beacon: Color(red: 0.98, green: 0.92, blue: 0.32),
                roomBorder: Color(red: 0.28, green: 0.63, blue: 0.88),
                roomHighlight: Color(red: 0.89, green: 0.92, blue: 0.99),
                roomShadow: Color.black.opacity(0.64),
                pattern: .circuit
            )
        default:
            return RegionTheme(
                floor: palette.ground,
                wall: palette.stone,
                water: palette.accentBlue,
                brush: palette.accentGreen,
                doorLocked: palette.titleGold,
                doorOpen: palette.lightGold,
                shrine: palette.accentViolet,
                stairs: palette.earth,
                beacon: palette.lightGold,
                roomBorder: palette.titleGold,
                roomHighlight: palette.lightGold,
                roomShadow: Color.black.opacity(0.55),
                pattern: .brick
            )
        }
    }
}

private enum MapOccupant {
    case none
    case player
    case npc(String)
    case enemy(String)
    case boss(String)
}

private enum MapFeature {
    case none
    case chest
    case bed
    case plateUp
    case plateDown
    case switchIdle
    case switchLit
    case shrine
    case beacon
    case gate
}

private struct LowResTileView: View {
    let tile: Tile
    let occupant: MapOccupant
    let feature: MapFeature
    let palette: UltimaPalette
    let regionTheme: RegionTheme

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().fill(tileColor)
                tilePattern(size: size)
                featureMark(size: size)
                sprite(size: size)
            }
            .overlay(
                Rectangle()
                    .stroke(tileEdgeColor, lineWidth: tile.type == .wall ? 1.6 : 0.6)
            )
        }
    }

    private var tileColor: Color {
        switch tile.type {
        case .floor: return regionTheme.floor
        case .wall: return regionTheme.wall
        case .water: return regionTheme.water
        case .brush: return regionTheme.brush
        case .doorLocked: return regionTheme.doorLocked
        case .doorOpen: return regionTheme.doorOpen
        case .shrine: return regionTheme.shrine
        case .stairs: return regionTheme.stairs
        case .beacon: return regionTheme.beacon
        }
    }

    private var tileEdgeColor: Color {
        if tile.type == .wall {
            return Color.black.opacity(0.65)
        }
        return Color.black.opacity(0.18)
    }

    @ViewBuilder
    private func tilePattern(size: CGFloat) -> some View {
        switch tile.type {
        case .floor:
            floorPattern(size: size)
        case .wall:
            ZStack {
                Rectangle()
                    .fill(regionTheme.roomHighlight.opacity(0.16))
                    .frame(width: size, height: max(2, size * 0.18))
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: max(2, size * 0.18), height: size)
            }
        case .water:
            VStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.white.opacity(0.20)).frame(width: size * 0.95, height: max(1, size * 0.10))
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size * 0.75, height: max(1, size * 0.10))
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.55, height: max(1, size * 0.10))
            }
        case .brush:
            HStack(alignment: .bottom, spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.45)
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.68)
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: max(1, size * 0.12), height: size * 0.52)
            }
        case .doorLocked, .doorOpen:
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: size * 0.52, height: size * 0.78)
                Rectangle()
                    .fill(regionTheme.roomHighlight.opacity(0.25))
                    .frame(width: max(1, size * 0.08), height: size * 0.62)
            }
        case .shrine:
            ZStack {
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.54, height: size * 0.54)
                Rectangle().fill(Color.black.opacity(0.15)).frame(width: size * 0.18, height: size * 0.70)
            }
        case .beacon:
            ZStack {
                Rectangle().fill(Color.white.opacity(0.22)).frame(width: size * 0.58, height: size * 0.58)
                Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.18, height: size * 0.82)
            }
        case .stairs:
            VStack(alignment: .trailing, spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.32, height: max(1, size * 0.10))
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: size * 0.52, height: max(1, size * 0.10))
                Rectangle().fill(Color.black.opacity(0.22)).frame(width: size * 0.72, height: max(1, size * 0.10))
            }
        }
    }

    @ViewBuilder
    private func floorPattern(size: CGFloat) -> some View {
        switch regionTheme.pattern {
        case .brick:
            VStack(spacing: max(1, size * 0.14)) {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.12)).frame(width: size, height: max(1, size * 0.08))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.clear).frame(width: size * 0.18)
                    Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.34, height: max(1, size * 0.08))
                    Spacer(minLength: 0)
                    Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.24, height: max(1, size * 0.08))
                }
            }
        case .speckle:
            ZStack {
                gemDot(x: size * 0.24, y: size * 0.28)
                gemDot(x: size * 0.68, y: size * 0.38)
                gemDot(x: size * 0.44, y: size * 0.68)
            }
        case .weave:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.12)).frame(width: max(1, size * 0.10), height: size)
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size, height: max(1, size * 0.10))
            }
        case .hash:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.78, height: max(1, size * 0.08)).rotationEffect(.degrees(45))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.08)).frame(width: size * 0.70, height: max(1, size * 0.08)).rotationEffect(.degrees(-45))
            }
        case .mire:
            VStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.14)).frame(width: size * 0.90, height: max(1, size * 0.08))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.08)).frame(width: size * 0.58, height: max(1, size * 0.08))
                Rectangle().fill(Color.black.opacity(0.10)).frame(width: size * 0.30, height: max(1, size * 0.08))
            }
        case .circuit:
            ZStack {
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: size * 0.74, height: max(1, size * 0.08))
                Rectangle().fill(regionTheme.roomHighlight.opacity(0.10)).frame(width: max(1, size * 0.08), height: size * 0.74)
                Rectangle().fill(Color.clear)
                    .frame(width: size * 0.54, height: size * 0.54)
                    .overlay(Rectangle().stroke(regionTheme.roomHighlight.opacity(0.10), lineWidth: max(1, size * 0.06)))
            }
        }
    }

    private func gemDot(x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(regionTheme.roomHighlight.opacity(0.12))
            .frame(width: max(1, x * 0.22), height: max(1, x * 0.22))
            .offset(x: x - (x * 0.11), y: y - (x * 0.11))
    }

    @ViewBuilder
    private func featureMark(size: CGFloat) -> some View {
        switch feature {
        case .none:
            EmptyView()
        case .chest:
            PixelSprite(color: palette.lightGold, pattern: [
                [0,1,1,0],
                [1,1,1,1],
                [1,0,0,1]
            ])
            .frame(width: size * 0.62, height: size * 0.54)
        case .bed:
            Rectangle().fill(palette.text).frame(width: size * 0.66, height: size * 0.20)
        case .plateUp:
            Rectangle().fill(palette.accentViolet).frame(width: size * 0.58, height: size * 0.16)
        case .plateDown:
            Rectangle().fill(Color.black.opacity(0.28)).frame(width: size * 0.58, height: size * 0.16)
        case .switchIdle:
            PixelSprite(color: palette.accentBlue, pattern: [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ])
            .frame(width: size * 0.48, height: size * 0.48)
        case .switchLit:
            PixelSprite(color: palette.lightGold, pattern: [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ])
            .frame(width: size * 0.48, height: size * 0.48)
        case .shrine:
            PixelSprite(color: palette.accentViolet, pattern: [
                [0,1,0],
                [1,1,1],
                [1,0,1],
                [0,1,0]
            ])
            .frame(width: size * 0.52, height: size * 0.62)
        case .beacon:
            PixelSprite(color: palette.lightGold, pattern: [
                [0,1,0],
                [1,1,1],
                [1,1,1],
                [0,1,0]
            ])
            .frame(width: size * 0.56, height: size * 0.64)
        case .gate:
            Rectangle().fill(palette.titleGold).frame(width: size * 0.40, height: size * 0.74)
        }
    }

    @ViewBuilder
    private func sprite(size: CGFloat) -> some View {
        switch occupant {
        case .none:
            EmptyView()
        case .player:
            gemstoneSprite(
                color: palette.text,
                pattern: [
                    [0,1,1,0],
                    [1,1,1,1],
                    [1,0,0,1],
                    [1,0,0,1]
                ],
                size: size * 0.78
            )
        case .npc(let id):
            gemstoneSprite(color: npcColor(for: id), pattern: npcPattern(for: id), size: size * 0.76)
        case .enemy(let id):
            gemstoneSprite(color: enemyColor(for: id), pattern: enemyPattern(for: id), size: size * 0.84)
        case .boss:
            gemstoneSprite(
                color: palette.accentViolet,
                pattern: [
                    [1,0,1,0,1],
                    [1,1,1,1,1],
                    [0,1,1,1,0],
                    [1,0,1,0,1]
                ],
                size: size * 0.90
            )
        }
    }

    private func gemstoneSprite(color: Color, pattern: [[Int]], size: CGFloat) -> some View {
        ZStack {
            PixelSprite(color: Color.black.opacity(0.45), pattern: pattern)
                .offset(x: size * 0.06, y: size * 0.06)
            PixelSprite(color: color, pattern: pattern)
        }
        .frame(width: size, height: size)
    }

    private func npcPattern(for id: String) -> [[Int]] {
        switch id {
        case "elder":
            return [
                [0,1,1,0],
                [1,1,1,1],
                [1,0,1,1],
                [1,0,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1,0],
                [0,1,1,1],
                [0,1,0,1],
                [0,1,0,1]
            ]
        case "orchard_guide":
            return [
                [0,1,1,0],
                [1,1,0,1],
                [0,1,1,1],
                [1,0,1,0]
            ]
        default:
            return [
                [0,1,1,0],
                [1,1,1,1],
                [0,1,1,0],
                [1,0,1,0]
            ]
        }
    }

    private func npcColor(for id: String) -> Color {
        switch id {
        case "elder":
            return palette.accentBlue
        case "field_scout":
            return palette.text
        case "orchard_guide":
            return palette.accentGreen
        case "barrow_scholar":
            return palette.accentViolet
        default:
            return palette.lightGold
        }
    }

    private func enemyPattern(for id: String) -> [[Int]] {
        if id.hasPrefix("crow") {
            return [
                [1,0,0,1],
                [1,1,1,1],
                [0,1,1,0],
                [0,1,0,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,1,0,0],
                [1,1,1,1],
                [0,1,1,1],
                [1,0,0,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,1,0],
                [1,1,1,1],
                [1,1,1,1],
                [1,0,1,1]
            ]
        }
        return [
            [1,1,1,1],
            [1,0,0,1],
            [1,1,1,1],
            [0,1,1,0]
        ]
    }

    private func enemyColor(for id: String) -> Color {
        if id.hasPrefix("crow") {
            return palette.text
        }
        if id.hasPrefix("hound") {
            return palette.titleGold
        }
        if id.hasPrefix("wraith") {
            return palette.accentBlue
        }
        return palette.lightGold
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
        .drawingGroup(opaque: false)
    }
}

private struct PixelPanel<Content: View>: View {
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

private struct PixelBanner: View {
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

private struct PixelStars: View {
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
        case "q": return .cancel
        case "x": return .quit
        default: return nil
        }
    }
}

private struct UltimaPalette {
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

private enum ChamberPattern {
    case brick
    case speckle
    case weave
    case hash
    case mire
    case circuit
}

private struct RegionTheme {
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
