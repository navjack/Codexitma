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

enum GraphicsVisualTheme: String, CaseIterable, Equatable {
    case gemstone
    case ultima
    case depth3D

    var displayName: String {
        switch self {
        case .gemstone:
            return "Gemstone"
        case .ultima:
            return "Ultima"
        case .depth3D:
            return "Depth 3D"
        }
    }

    var summary: String {
        switch self {
        case .gemstone:
            return "Bright chamber borders, black void framing, and chunkier sprites."
        case .ultima:
            return "Cleaner overworld boards with flatter tiles and a stricter classic field look."
        case .depth3D:
            return "A first-person pseudo-3D dungeon view that reads the same live map."
        }
    }

    func next() -> GraphicsVisualTheme {
        switch self {
        case .gemstone:
            return .ultima
        case .ultima:
            return .depth3D
        case .depth3D:
            return .gemstone
        }
    }
}

@MainActor
final class GameSessionController: ObservableObject {
    @Published private(set) var state: GameState
    @Published private(set) var visualTheme: GraphicsVisualTheme = .gemstone

    private let engine: GameEngine
    private let preferenceStore: GraphicsPreferenceStore
    private let soundEngine: AppleIISoundEngine

    init(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil,
        preferenceStore: GraphicsPreferenceStore = .shared,
        soundEngine: AppleIISoundEngine = .shared
    ) {
        self.preferenceStore = preferenceStore
        self.soundEngine = soundEngine
        let engine = GameEngine(library: library, saveRepository: saveRepository)
        if let playtestAdventureID {
            engine.beginPlaytest(for: playtestAdventureID)
        }
        self.engine = engine
        self.state = engine.state
        self.visualTheme = preferenceStore.loadTheme()
        soundEngine.play(.introMusic)
    }

    func send(_ command: ActionCommand) {
        let previous = state
        let resolved = resolvedCommand(for: command)
        engine.handle(resolved)
        state = engine.state
        playSound(for: resolved, previous: previous, current: state)
        if state.shouldQuit {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func cycleVisualTheme() {
        visualTheme = visualTheme.next()
        preferenceStore.saveTheme(visualTheme)
    }

    func selectVisualTheme(_ theme: GraphicsVisualTheme) {
        visualTheme = theme
        preferenceStore.saveTheme(theme)
    }

    private func resolvedCommand(for command: ActionCommand) -> ActionCommand {
        guard visualTheme == .depth3D, state.mode == .exploration else {
            return command
        }

        switch command {
        case .move(.up):
            return .move(state.player.facing)
        case .move(.down):
            return .moveBackward
        case .move(.left):
            return .turnLeft
        case .move(.right):
            return .turnRight
        default:
            return command
        }
    }

    private func playSound(for command: ActionCommand, previous: GameState, current: GameState) {
        if previous.mode == .title && current.mode == .characterCreation {
            soundEngine.play(.menuConfirm)
            return
        }

        if previous.mode == .characterCreation && current.mode == .exploration {
            soundEngine.play(.menuConfirm)
            return
        }

        if isMovementCommand(command) {
            if previous.player.position != current.player.position {
                soundEngine.play(.walk)
                return
            }

            let enemyRosterChanged = previous.world.enemies != current.world.enemies
            let healthChanged = previous.player.health != current.player.health
            if enemyRosterChanged || healthChanged {
                soundEngine.play(.attack)
                return
            }
        }

        if isTurnCommand(command), previous.player.facing != current.player.facing {
            soundEngine.play(.menuConfirm)
            return
        }

        let usedItem = previous.mode == .inventory && current.mode == .exploration &&
            (
                previous.player.inventory.count != current.player.inventory.count ||
                previous.player.equipment != current.player.equipment ||
                previous.player.health != current.player.health ||
                previous.player.lanternCharge != current.player.lanternCharge
            )
        if usedItem {
            soundEngine.play(.useItem)
            return
        }

        let boughtFromShop = previous.mode == .shop && current.mode == .shop &&
            (
                previous.player.marks != current.player.marks ||
                previous.player.inventory.count != current.player.inventory.count ||
                previous.player.equipment != current.player.equipment
            )
        if boughtFromShop {
            soundEngine.play(.useItem)
            return
        }

        if (command == .interact || command == .confirm), previous.mode == .exploration, current.mode == .shop {
            soundEngine.play(.menuConfirm)
            return
        }

        if command == .interact || command == .confirm, previous.mode == .exploration, current.mode == .dialogue {
            soundEngine.play(.menuConfirm)
        }
    }

    private func isMovementCommand(_ command: ActionCommand) -> Bool {
        switch command {
        case .move, .moveBackward:
            return true
        default:
            return false
        }
    }

    private func isTurnCommand(_ command: ActionCommand) -> Bool {
        switch command {
        case .turnLeft, .turnRight:
            return true
        default:
            return false
        }
    }
}

@MainActor
enum GraphicsGameLauncher {
    private static var retainedDelegate: GraphicsAppDelegate?

    static func run(
        library: GameContentLibrary,
        saveRepository: SaveRepository,
        playtestAdventureID: AdventureID? = nil
    ) {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let session = GameSessionController(
            library: library,
            saveRepository: saveRepository,
            playtestAdventureID: playtestAdventureID
        )
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
            PixelStars(color: starfieldColor).ignoresSafeArea()
            PixelKeyCapture(
                onCommand: { session.send($0) },
                onThemeToggle: { session.cycleVisualTheme() }
            )
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
        return VStack(spacing: 16) {
            Spacer()
            PixelBanner(text: "CODEXITMA", color: palette.titleGold)
            Text("A LOW-RES APPLE II FANTASY")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.text)
            Text("\(session.state.selectedAdventureTitle().uppercased()) // CLASSES, TRAITS, AND LOW-RES LEGENDS")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.accentBlue)

            HStack(spacing: 10) {
                menuButton("A: PREV") { session.send(.move(.left)) }
                menuButton("D: NEXT") { session.send(.move(.right)) }
                menuButton("N: CREATE") { session.send(.newGame) }
                menuButton("L: LOAD") { session.send(.load) }
                menuButton("X: QUIT") { session.send(.quit) }
            }
            .frame(maxWidth: 900)

            Text(session.state.selectedAdventureSummary().uppercased())
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.9))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 820)

            HStack(spacing: 10) {
                menuButton("T: STYLE") { session.cycleVisualTheme() }
                    .frame(width: 150)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DISPLAY \(session.visualTheme.displayName.uppercased())")
                    Text(session.visualTheme.summary.uppercased())
                        .lineLimit(2)
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.9))
            }
            .frame(maxWidth: 760)

            VStack(spacing: 4) {
                Text("\(session.visualTheme.displayName.uppercased()) DISPLAY ACTIVE. CREATE A HERO BEFORE YOU ENTER THE VALLEY")
                Text("A/D PICK ADVENTURE   ARROWS/WASD STEP ROOM TO ROOM")
                Text("E TALK OR USE   I OPEN PACK")
                Text("J SHOW GOAL   K SAVE   L LOAD   T SWITCH STYLE")
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
            Text(session.state.selectedAdventureTitle().uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.accentBlue)

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
                menuButton("T: STYLE") { session.cycleVisualTheme() }
                Text(session.visualTheme.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.accentBlue)
                menuButton("E: BEGIN") { session.send(.confirm) }
                menuButton("Q: BACK") { session.send(.cancel) }
            }
            .frame(width: 520)
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
                    PixelPanel(title: mapPanelTitle, palette: palette) {
                        MapBoardView(state: session.state, palette: palette, visualTheme: session.visualTheme)
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
                        commercePanel
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
                stat("MARKS", "\(session.state.player.marks)")
                stat("BAG", "\(session.state.player.inventory.count)/\(session.state.player.inventoryCapacity())")
                stat("STYLE", session.visualTheme.displayName.uppercased())
                stat("GOAL", QuestSystem.objective(for: session.state.quests, flow: session.state.questFlow).uppercased())

                menuButton("T: STYLE") { session.cycleVisualTheme() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commercePanel: some View {
        Group {
            if session.state.mode == .shop {
                shopPanel
            } else {
                packPanel
            }
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
                    ForEach(visibleInventoryRows, id: \.index) { row in
                        let isSelected = row.index == session.state.inventorySelectionIndex
                        HStack(spacing: 5) {
                            Text(isSelected ? ">" : " ")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(isSelected ? palette.background : palette.text)
                            Rectangle()
                                .fill(itemColor(row.item))
                                .frame(width: 8, height: 8)
                            Text(row.item.name.uppercased())
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(isSelected ? palette.background : palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(isSelected ? palette.lightGold : .clear)
                    }
                }

                if session.state.mode == .inventory, let selected = selectedInventoryItem {
                    Text("SEL \(selected.name.uppercased())")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)
                        .padding(.top, 4)
                    Text("E USE  R DROP  Q LEAVE")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.82))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shopPanel: some View {
        PixelPanel(title: "SHOP", palette: palette) {
            VStack(alignment: .leading, spacing: 4) {
                Text((session.state.shopTitle ?? "MERCHANT").uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.lightGold)
                    .lineLimit(2)

                ForEach(Array(session.state.shopOffers.enumerated()), id: \.offset) { index, offer in
                    let itemName = itemTable[offer.itemID]?.name.uppercased() ?? offer.itemID.rawValue.uppercased()
                    let soldOut = !offer.repeatable && session.state.world.purchasedShopOffers.contains(offer.id)

                    HStack(spacing: 5) {
                        Text(index == session.state.shopSelectionIndex ? ">" : " ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.text)
                        Text(itemName)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(soldOut ? "SOLD" : "\(offer.price)M")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(soldOut ? palette.accentBlue : palette.lightGold)
                    }
                }

                if let detail = session.state.shopDetail {
                    Text(detail.uppercased())
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                HStack(spacing: 8) {
                    menuButton("E: BUY") { session.send(.interact) }
                    menuButton("Q: LEAVE") { session.send(.cancel) }
                }
                .padding(.top, 4)
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
                Text(movementHintLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(inputPrimaryLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(inputSecondaryLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(inputTertiaryLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        menuButton("I") { session.send(.openInventory) }
                        menuButton("J") { session.send(.help) }
                        menuButton("E") { session.send(.interact) }
                    }
                    HStack(spacing: 8) {
                        if session.state.mode == .inventory {
                            menuButton("R") { session.send(.dropInventoryItem) }
                            menuButton("K") { session.send(.save) }
                            menuButton("Q") { session.send(.cancel) }
                        } else {
                            menuButton("K") { session.send(.save) }
                            menuButton("L") { session.send(.load) }
                            menuButton("X") { session.send(.quit) }
                        }
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

    private var mapPanelTitle: String {
        switch session.visualTheme {
        case .gemstone:
            return "\(currentMapName.uppercased()) CHAMBER"
        case .ultima:
            return "\(currentMapName.uppercased()) OVERWORLD"
        case .depth3D:
            return "\(currentMapName.uppercased()) DEPTH"
        }
    }

    private var movementHintLine: String {
        if session.state.mode == .shop || session.state.mode == .inventory {
            return "ARROWS/WASD BROWSE"
        }
        if session.visualTheme == .depth3D {
            return "W/UP FWD  S/DN BACK"
        }
        return "ARROWS/WASD MOVE"
    }

    private var starfieldColor: Color {
        switch session.visualTheme {
        case .gemstone:
            return palette.accentBlue
        case .ultima:
            return palette.accentGreen
        case .depth3D:
            return palette.accentViolet
        }
    }

    private var visibleInventoryRows: [(index: Int, item: Item)] {
        let items = session.state.player.inventory
        guard !items.isEmpty else { return [] }

        let selection = session.state.inventorySelectionIndex
        let windowSize = 5
        let start: Int
        if items.count <= windowSize {
            start = 0
        } else {
            let centered = selection - (windowSize / 2)
            start = max(0, min(centered, items.count - windowSize))
        }

        return Array(items.enumerated().dropFirst(start).prefix(windowSize)).map { ($0.offset, $0.element) }
    }

    private var selectedInventoryItem: Item? {
        guard !session.state.player.inventory.isEmpty else { return nil }
        let index = max(0, min(session.state.inventorySelectionIndex, session.state.player.inventory.count - 1))
        return session.state.player.inventory[index]
    }

    private var inputPrimaryLine: String {
        switch session.state.mode {
        case .shop:
            return "E BUY   J INFO   Q LEAVE"
        case .inventory:
            return "E USE   R DROP   Q LEAVE"
        default:
            if session.visualTheme == .depth3D {
                return "A/D TURN  E ACT  I PACK"
            }
            return "E ACT   I PACK   Q BACK"
        }
    }

    private var inputSecondaryLine: String {
        switch session.state.mode {
        case .shop:
            return "K SAVE  L LOAD  X QUIT"
        case .inventory:
            return "J INFO  K SAVE  L LOAD"
        default:
            return "J GOAL  K SAVE  L LOAD"
        }
    }

    private var inputTertiaryLine: String {
        switch session.state.mode {
        case .shop:
            return "T STYLE  I ALSO LEAVES"
        case .inventory:
            return "T STYLE  I ALSO LEAVES"
        default:
            if session.visualTheme == .depth3D {
                return "Q BACK  T STYLE  X QUIT"
            }
            return "T STYLE  X QUIT"
        }
    }
}

private struct MapBoardView: View {
    let state: GameState
    let palette: UltimaPalette
    let visualTheme: GraphicsVisualTheme

    private let cell: CGFloat = 14

    var body: some View {
        if visualTheme == .depth3D {
            firstPersonView(theme: regionTheme)
        } else {
            topDownView(map: state.world.maps[state.player.currentMapID], theme: regionTheme)
        }
    }

    private func topDownView(map: MapDefinition?, theme: RegionTheme) -> some View {
        let boardPadding = visualTheme == .gemstone ? 4.0 : 2.0
        let boardScale = visualTheme == .gemstone ? 2.0 : 1.84
        let boardWidth = CGFloat(map?.lines.first?.count ?? 0) * cell
        let boardHeight = CGFloat(map?.lines.count ?? 0) * cell

        return ZStack(alignment: .topLeading) {
            if visualTheme == .gemstone {
                Rectangle()
                    .fill(theme.roomShadow)
                    .offset(x: 3, y: 3)
            }

            VStack(spacing: 0) {
                ForEach(Array((map?.lines ?? []).enumerated()), id: \.offset) { y, line in
                    HStack(spacing: 0) {
                        ForEach(Array(line.enumerated()), id: \.offset) { x, raw in
                            LowResTileView(
                                tile: TileFactory.tile(for: resolved(raw)),
                                occupant: occupant(at: Position(x: x, y: y)),
                                feature: feature(at: Position(x: x, y: y)),
                                palette: palette,
                                regionTheme: theme,
                                visualTheme: visualTheme
                            )
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .padding(boardPadding)
            .background(visualTheme == .gemstone ? Color.black : theme.floor.opacity(0.22))
            .overlay(
                Rectangle()
                    .stroke(
                        visualTheme == .gemstone ? theme.roomHighlight : palette.lightGold.opacity(0.75),
                        lineWidth: visualTheme == .gemstone ? 2 : 1
                    )
                    .padding(visualTheme == .gemstone ? 3 : 0)
            )
            .overlay(
                Rectangle()
                    .stroke(
                        visualTheme == .gemstone ? theme.roomBorder : palette.lightGold,
                        lineWidth: visualTheme == .gemstone ? 4 : 2
                    )
            )
        }
        .scaleEffect(boardScale, anchor: .topLeading)
        .frame(
            width: (boardWidth + (boardPadding * 2)) * boardScale,
            height: (boardHeight + (boardPadding * 2)) * boardScale,
            alignment: .topLeading
        )
        .clipped()
        .drawingGroup(opaque: false)
    }

    private func firstPersonView(theme: RegionTheme) -> some View {
        GeometryReader { proxy in
            let raySamples = depthRaySamples(columns: 96, maxDistance: 9.0)
            ZStack {
                Canvas { context, canvasSize in
                    drawDepthScene(into: &context, size: canvasSize, samples: raySamples, theme: theme)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("VIEW \(state.player.facing.shortLabel)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)
                    Text("FIRST-PERSON")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.86))
                    Text("RAYCAST MAP  A/D TURN")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                    Text("W/S STEP  RANGE 9 TILES")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.76))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)

                CrosshairView(color: palette.text.opacity(0.65))
                    .frame(width: 26, height: 26)
            }
            .overlay(
                Rectangle()
                    .stroke(theme.roomHighlight.opacity(0.65), lineWidth: 2)
                    .padding(4)
            )
            .overlay(
                Rectangle()
                    .stroke(theme.roomBorder, lineWidth: 4)
            )
            .drawingGroup(opaque: false)
        }
        .frame(width: 584, height: 356)
    }

    private func depthRaySamples(columns: Int, maxDistance: Double) -> [DepthRaySample] {
        let origin = CGPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let caster = DepthRaycaster(origin: origin, facing: state.player.facing, fov: depthFieldOfView) { position in
            tile(at: position)
        }
        return caster.castSamples(columns: columns, maxDistance: maxDistance)
    }

    private func drawDepthScene(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        drawDepthBackdrop(into: &context, size: size, theme: theme)
        drawDepthWalls(into: &context, size: size, samples: samples, theme: theme)
        drawDepthBillboards(into: &context, size: size, samples: samples, theme: theme)
        drawDepthReticleGlow(into: &context, size: size)
    }

    private func drawDepthBackdrop(
        into context: inout GraphicsContext,
        size: CGSize,
        theme: RegionTheme
    ) {
        let horizon = size.height * 0.5
        let ceilingRect = CGRect(x: 0, y: 0, width: size.width, height: horizon)
        let floorRect = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)

        if usesSkyBackdrop {
            context.fill(
                Path(ceilingRect),
                with: .linearGradient(
                    Gradient(colors: [
                        theme.roomHighlight.opacity(0.34),
                        theme.roomShadow.opacity(0.86)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: horizon)
                )
            )

            for band in 0..<5 {
                let y = horizon * (0.12 + (CGFloat(band) * 0.13))
                let width = size.width * (0.16 + (CGFloat(band % 3) * 0.08))
                let x = (size.width * 0.18) + (CGFloat((band * 17) % 41) / 100.0) * size.width
                let cloud = CGRect(x: min(x, size.width - width), y: y, width: width, height: 3)
                context.fill(Path(cloud), with: .color(theme.roomHighlight.opacity(0.08)))
            }
        } else {
            context.fill(
                Path(ceilingRect),
                with: .linearGradient(
                    Gradient(colors: [
                        Color.black.opacity(0.98),
                        theme.wall.opacity(0.34)
                    ]),
                    startPoint: CGPoint(x: size.width * 0.5, y: 0),
                    endPoint: CGPoint(x: size.width * 0.5, y: horizon)
                )
            )

            for row in 1...8 {
                let t = CGFloat(row) / 8.0
                let y = horizon * pow(t, 1.65)
                let line = Path(CGRect(x: 0, y: y, width: size.width, height: 1))
                context.fill(line, with: .color(theme.roomHighlight.opacity(0.05)))
            }
        }

        context.fill(Path(floorRect), with: .color(theme.floor.opacity(0.18)))

        let floorBands = 14
        for band in 0..<floorBands {
            let t0 = CGFloat(band) / CGFloat(floorBands)
            let t1 = CGFloat(band + 1) / CGFloat(floorBands)
            let y0 = horizon + (size.height - horizon) * pow(t0, 1.6)
            let y1 = horizon + (size.height - horizon) * pow(t1, 1.6)
            let rect = CGRect(x: 0, y: y0, width: size.width, height: max(1, y1 - y0))
            let shade = 0.10 + (Double(t1) * 0.22)
            let stripe = band.isMultiple(of: 2) ? theme.roomHighlight.opacity(0.05) : Color.black.opacity(0.04)
            context.fill(Path(rect), with: .color(theme.floor.opacity(shade)))
            context.fill(Path(rect.insetBy(dx: 0, dy: 0)), with: .color(stripe))

            if band > 0 {
                let line = Path(CGRect(x: 0, y: y0, width: size.width, height: 1))
                context.fill(line, with: .color(theme.roomHighlight.opacity(0.06)))
            }
        }

        let center = CGPoint(x: size.width * 0.5, y: horizon)
        for step in stride(from: -0.8, through: 0.8, by: 0.2) {
            let end = CGPoint(x: size.width * (0.5 + (step * 0.55)), y: size.height)
            var guide = Path()
            guide.move(to: center)
            guide.addLine(to: end)
            context.stroke(guide, with: .color(theme.roomHighlight.opacity(0.04)), lineWidth: 1)
        }

        let horizonLine = Path(CGRect(x: 0, y: horizon, width: size.width, height: 1))
        context.fill(horizonLine, with: .color(theme.roomHighlight.opacity(0.10)))
    }

    private func drawDepthWalls(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        guard !samples.isEmpty else { return }

        let horizon = size.height * 0.5
        let columnWidth = size.width / CGFloat(samples.count)

        for sample in samples where sample.didHit {
            let distance = max(0.14, sample.correctedDistance)
            let wallHeight = min(size.height * 0.92, (size.height * 0.82) / CGFloat(distance))
            let top = max(0, horizon - (wallHeight * 0.5))
            let rect = CGRect(
                x: CGFloat(sample.column) * columnWidth,
                y: top,
                width: ceil(columnWidth) + 1,
                height: min(size.height - top, wallHeight)
            )

            let axisShade = sample.hitAxis == .vertical ? 0.78 : 0.92
            let distanceShade = max(0.20, 1.0 - ((sample.correctedDistance / sample.maxDistance) * 0.76))
            let wallColor = frontWallColor(for: sample.hitTile, theme: theme).opacity(distanceShade * axisShade)
            context.fill(Path(rect), with: .color(wallColor))

            if sample.column.isMultiple(of: 3) {
                let stripe = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: max(1, rect.width * 0.34),
                    height: rect.height
                )
                context.fill(Path(stripe), with: .color(Color.black.opacity(0.08)))
            }

            let topEdge = Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1))
            context.fill(topEdge, with: .color(theme.roomHighlight.opacity(0.12)))
        }
    }

    private func drawDepthBillboards(
        into context: inout GraphicsContext,
        size: CGSize,
        samples: [DepthRaySample],
        theme: RegionTheme
    ) {
        guard !samples.isEmpty else { return }

        let zBuffer = samples.map(\.correctedDistance)
        let billboards = depthBillboards(maxDistance: samples.first?.maxDistance ?? 9.0)
            .sorted { $0.distance > $1.distance }
        let horizon = size.height * 0.5
        let columnWidth = size.width / CGFloat(samples.count)

        for billboard in billboards {
            let screenCenter = ((billboard.angleOffset / depthFieldOfView) + 0.5) * size.width
            let projectedHeight = min(
                size.height * 0.88,
                CGFloat((size.height * billboard.scale) / max(0.16, billboard.distance))
            )
            let aspect = CGFloat(max(1, billboard.pattern.first?.count ?? 1)) / CGFloat(max(1, billboard.pattern.count))
            let projectedWidth = max(10, projectedHeight * aspect * billboard.widthScale)
            let left = screenCenter - (projectedWidth / 2)
            let top = horizon - (projectedHeight * 0.5)
            let cellWidth = projectedWidth / CGFloat(max(1, billboard.pattern.first?.count ?? 1))
            let cellHeight = projectedHeight / CGFloat(max(1, billboard.pattern.count))
            let shade = max(0.28, 1.0 - ((billboard.distance / billboard.maxDistance) * 0.72))
            let color = billboard.color.opacity(shade)

            for patternColumn in 0..<max(1, billboard.pattern.first?.count ?? 1) {
                let stripeMinX = left + (CGFloat(patternColumn) * cellWidth)
                let stripeMaxX = stripeMinX + cellWidth
                let startSample = max(0, Int(floor(stripeMinX / columnWidth)))
                let endSample = min(samples.count - 1, Int(floor(max(stripeMinX, stripeMaxX - 1) / columnWidth)))
                if startSample > endSample {
                    continue
                }

                var visible = false
                for sampleIndex in startSample...endSample where billboard.distance <= (zBuffer[sampleIndex] + 0.06) {
                    visible = true
                    break
                }
                if !visible {
                    continue
                }

                for patternRow in 0..<billboard.pattern.count where billboard.pattern[patternRow][patternColumn] == 1 {
                    let rect = CGRect(
                        x: stripeMinX,
                        y: top + (CGFloat(patternRow) * cellHeight),
                        width: max(1, cellWidth),
                        height: max(1, cellHeight)
                    )
                    context.fill(Path(rect), with: .color(color))

                    if patternColumn == 0 || patternColumn == (billboard.pattern.first?.count ?? 1) - 1 {
                        let edge = CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
                        context.fill(Path(edge), with: .color(Color.black.opacity(0.18)))
                    }
                }
            }
        }
    }

    private func drawDepthReticleGlow(
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        let glow = CGRect(
            x: (size.width * 0.5) - 3,
            y: (size.height * 0.5) - 3,
            width: 6,
            height: 6
        )
        context.fill(Path(ellipseIn: glow), with: .color(palette.lightGold.opacity(0.05)))
    }

    private func depthBillboards(maxDistance: Double) -> [DepthBillboard] {
        guard let map = state.world.maps[state.player.currentMapID] else { return [] }

        let playerCenter = CGPoint(
            x: Double(state.player.position.x) + 0.5,
            y: Double(state.player.position.y) + 0.5
        )
        let forward = facingUnitVector
        let right = rightUnitVector
        var billboards: [DepthBillboard] = []

        for y in 0..<map.lines.count {
            let line = Array(map.lines[y])
            for x in 0..<line.count {
                let position = Position(x: x, y: y)
                if position == state.player.position {
                    continue
                }

                let worldX = Double(x) + 0.5
                let worldY = Double(y) + 0.5
                let dx = worldX - playerCenter.x
                let dy = worldY - playerCenter.y
                let forwardDistance = (dx * forward.x) + (dy * forward.y)
                if forwardDistance <= 0.05 {
                    continue
                }

                let sideDistance = (dx * right.x) + (dy * right.y)
                let distance = hypot(dx, dy)
                if distance > maxDistance {
                    continue
                }

                let angleOffset = atan2(sideDistance, forwardDistance)
                if abs(angleOffset) > (depthFieldOfView * 0.65) {
                    continue
                }

                if let billboard = depthBillboard(at: position, distance: distance, angleOffset: angleOffset, maxDistance: maxDistance) {
                    billboards.append(billboard)
                }
            }
        }

        return billboards
    }

    private func depthBillboard(
        at position: Position,
        distance: Double,
        angleOffset: Double,
        maxDistance: Double
    ) -> DepthBillboard? {
        if let enemy = state.world.enemies.first(where: {
            $0.active && $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return DepthBillboard(
                id: "enemy:\(enemy.id):\(position.x):\(position.y)",
                pattern: firstPersonEnemyPattern(for: enemy.id),
                color: firstPersonEnemyColor(for: enemy.id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.78,
                widthScale: 0.70
            )
        }

        if let npc = state.world.npcs.first(where: {
            $0.mapID == state.player.currentMapID && $0.position == position
        }) {
            return DepthBillboard(
                id: "npc:\(npc.id):\(position.x):\(position.y)",
                pattern: firstPersonNPCPattern(for: npc.id),
                color: firstPersonNPCColor(for: npc.id),
                distance: distance,
                angleOffset: angleOffset,
                maxDistance: maxDistance,
                scale: 0.72,
                widthScale: 0.68
            )
        }

        let feature = feature(at: position)
        guard feature != .none else { return nil }
        guard let appearance = depthFeatureAppearance(for: feature) else { return nil }
        return DepthBillboard(
            id: "feature:\(position.x):\(position.y):\(feature.debugName)",
            pattern: appearance.pattern,
            color: appearance.color,
            distance: distance,
            angleOffset: angleOffset,
            maxDistance: maxDistance,
            scale: appearance.scale,
            widthScale: appearance.widthScale
        )
    }

    private func depthFeatureAppearance(for feature: MapFeature) -> (pattern: [[Int]], color: Color, scale: Double, widthScale: CGFloat)? {
        switch feature {
        case .none:
            return nil
        case .chest:
            return (
                [
                    [1,1,1],
                    [1,0,1]
                ],
                palette.lightGold,
                0.44,
                0.84
            )
        case .bed:
            return (
                [
                    [1,1,1],
                    [1,0,0]
                ],
                palette.text,
                0.34,
                1.10
            )
        case .plateUp:
            return (
                [
                    [1,1],
                    [1,1]
                ],
                palette.accentViolet,
                0.22,
                1.30
            )
        case .plateDown:
            return (
                [
                    [1,1]
                ],
                palette.text.opacity(0.65),
                0.16,
                1.45
            )
        case .switchIdle:
            return (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                palette.accentBlue,
                0.28,
                0.84
            )
        case .switchLit:
            return (
                [
                    [1,1,1],
                    [1,1,1],
                    [1,1,1]
                ],
                palette.lightGold,
                0.28,
                0.84
            )
        case .shrine:
            return (
                [
                    [0,1,0],
                    [1,1,1],
                    [0,1,0]
                ],
                regionTheme.shrine,
                0.46,
                0.90
            )
        case .beacon:
            return (
                [
                    [0,1,0],
                    [1,1,1],
                    [1,1,1]
                ],
                regionTheme.beacon,
                0.54,
                0.92
            )
        case .gate:
            return (
                [
                    [1,0,1],
                    [1,0,1],
                    [1,1,1]
                ],
                regionTheme.doorLocked,
                0.62,
                1.05
            )
        }
    }

    private var depthFieldOfView: Double {
        .pi / 3.1
    }

    private var facingUnitVector: (x: Double, y: Double) {
        switch state.player.facing {
        case .up:
            return (0, -1)
        case .down:
            return (0, 1)
        case .left:
            return (-1, 0)
        case .right:
            return (1, 0)
        }
    }

    private var rightUnitVector: (x: Double, y: Double) {
        switch state.player.facing {
        case .up:
            return (1, 0)
        case .down:
            return (-1, 0)
        case .left:
            return (0, -1)
        case .right:
            return (0, 1)
        }
    }

    private var usesSkyBackdrop: Bool {
        let mapID = state.player.currentMapID
        let indoorFragments = [
            "barrow",
            "spire",
            "vault",
            "archive",
            "observatory",
            "cloister",
            "keep",
            "catacomb",
            "crypt",
            "sanctum"
        ]
        return indoorFragments.allSatisfy { !mapID.contains($0) }
    }

    private func corridorLayer(for slice: CorridorSlice, in size: CGSize, theme: RegionTheme) -> some View {
        let near = perspectiveFrame(depth: slice.depth, in: size)
        let far = perspectiveFrame(depth: slice.depth + 1, in: size)

        return ZStack {
            quad(
                near.bottomLeft,
                near.bottomRight,
                far.bottomRight,
                far.bottomLeft
            )
            .fill(theme.floor.opacity(0.24 + (Double(slice.depth) * 0.08)))

            quad(
                near.topLeft,
                near.topRight,
                far.topRight,
                far.topLeft
            )
            .fill(Color.white.opacity(0.015 + (Double(slice.depth) * 0.01)))

            if slice.leftBlocked {
                quad(
                    near.topLeft,
                    far.topLeft,
                    far.bottomLeft,
                    near.bottomLeft
                )
                .fill(sideWallColor(for: slice.leftTile, theme: theme, brightness: 0.90 - (Double(slice.depth) * 0.12)))
            } else {
                corridorGuide(from: near.topLeft, to: far.topLeft, intensity: 0.32)
                corridorGuide(from: near.bottomLeft, to: far.bottomLeft, intensity: 0.22)
            }

            if slice.rightBlocked {
                quad(
                    near.topRight,
                    far.topRight,
                    far.bottomRight,
                    near.bottomRight
                )
                .fill(sideWallColor(for: slice.rightTile, theme: theme, brightness: 1.0 - (Double(slice.depth) * 0.12)))
            } else {
                corridorGuide(from: near.topRight, to: far.topRight, intensity: 0.32)
                corridorGuide(from: near.bottomRight, to: far.bottomRight, intensity: 0.22)
            }

            if slice.frontBlocked {
                Rectangle()
                    .fill(frontWallColor(for: slice.frontTile, theme: theme))
                    .frame(width: far.width, height: far.height)
                    .position(x: far.center.x, y: far.center.y)
                    .overlay(
                        Rectangle()
                            .stroke(theme.roomHighlight.opacity(0.48), lineWidth: 2)
                            .frame(width: far.width, height: far.height)
                            .position(x: far.center.x, y: far.center.y)
                    )
            } else {
                Rectangle()
                    .stroke(theme.roomHighlight.opacity(0.18), lineWidth: 1)
                    .frame(width: far.width, height: far.height)
                    .position(x: far.center.x, y: far.center.y)
            }

            if let feature = firstPersonFeature(for: slice.feature, theme: theme, in: far) {
                feature
            }

            if let sprite = firstPersonOccupant(for: slice.occupant, in: far) {
                sprite
            }
        }
    }

    private func firstPersonFeature(for feature: MapFeature, theme: RegionTheme, in frame: PerspectiveFrame) -> AnyView? {
        let color: Color
        let pattern: [[Int]]

        switch feature {
        case .none:
            return nil
        case .chest:
            color = palette.lightGold
            pattern = [
                [1,1,1],
                [1,0,1]
            ]
        case .bed:
            color = palette.text
            pattern = [
                [1,1,1],
                [1,0,0]
            ]
        case .plateUp:
            color = palette.accentViolet
            pattern = [
                [1,1],
                [1,1]
            ]
        case .plateDown:
            color = palette.text.opacity(0.65)
            pattern = [
                [1,1]
            ]
        case .switchIdle:
            color = palette.accentBlue
            pattern = [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        case .switchLit:
            color = palette.lightGold
            pattern = [
                [1,1,1],
                [1,1,1],
                [1,1,1]
            ]
        case .shrine:
            color = theme.shrine
            pattern = [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        case .beacon:
            color = theme.beacon
            pattern = [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        case .gate:
            color = theme.doorLocked
            pattern = [
                [1,0,1],
                [1,0,1],
                [1,1,1]
            ]
        }

        let spriteHeight = max(12, frame.height * 0.34)
        let spriteWidth = max(12, frame.width * 0.18)
        let view = PixelSprite(color: color, pattern: pattern)
            .frame(width: spriteWidth, height: spriteHeight)
            .position(x: frame.center.x, y: frame.bottomLeft.y - (spriteHeight * 0.55))
        return AnyView(view)
    }

    private func firstPersonOccupant(for occupant: MapOccupant, in frame: PerspectiveFrame) -> AnyView? {
        let color: Color
        let pattern: [[Int]]

        switch occupant {
        case .none:
            return nil
        case .player:
            color = palette.text
            pattern = [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case .npc(let id):
            color = firstPersonNPCColor(for: id)
            pattern = firstPersonNPCPattern(for: id)
        case .enemy(let id):
            color = firstPersonEnemyColor(for: id)
            pattern = firstPersonEnemyPattern(for: id)
        case .boss:
            color = palette.accentViolet
            pattern = [
                [1,0,1],
                [1,1,1],
                [1,1,1]
            ]
        }

        let spriteHeight = max(18, frame.height * 0.62)
        let spriteWidth = max(18, frame.width * 0.34)
        let view = ZStack {
            PixelSprite(color: Color.black.opacity(0.42), pattern: pattern)
                .offset(x: spriteWidth * 0.04, y: spriteHeight * 0.04)
            PixelSprite(color: color, pattern: pattern)
        }
        .frame(width: spriteWidth, height: spriteHeight)
        .position(x: frame.center.x, y: frame.bottomLeft.y - (spriteHeight * 0.38))
        return AnyView(view)
    }

    private func corridorGuide(from start: CGPoint, to end: CGPoint, intensity: Double) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(palette.text.opacity(intensity), lineWidth: 1)
    }

    private func perspectiveFrame(depth: Int, in size: CGSize) -> PerspectiveFrame {
        let factors: [CGFloat] = [0.04, 0.14, 0.26, 0.36, 0.44]
        let safeDepth = max(0, min(depth, factors.count - 1))
        let inset = min(size.width, size.height) * factors[safeDepth]
        let horizontal = inset * 1.22
        let vertical = inset * 0.82
        let left = horizontal
        let right = size.width - horizontal
        let top = vertical
        let bottom = size.height - vertical
        return PerspectiveFrame(
            topLeft: CGPoint(x: left, y: top),
            topRight: CGPoint(x: right, y: top),
            bottomLeft: CGPoint(x: left, y: bottom),
            bottomRight: CGPoint(x: right, y: bottom)
        )
    }

    private func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        Path { path in
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.addLine(to: d)
            path.closeSubpath()
        }
    }

    private func corridorSlices(maxDepth: Int = 4) -> [CorridorSlice] {
        var slices: [CorridorSlice] = []
        guard state.world.maps[state.player.currentMapID] != nil else { return slices }

        for depth in 0..<maxDepth {
            let frontPosition = advancedPosition(from: state.player.position, direction: state.player.facing, steps: depth + 1)
            let frontTile = tile(at: frontPosition)
            let leftTile = tile(at: advancedPosition(from: frontPosition, direction: state.player.facing.leftTurn, steps: 1))
            let rightTile = tile(at: advancedPosition(from: frontPosition, direction: state.player.facing.rightTurn, steps: 1))
            let slice = CorridorSlice(
                depth: depth,
                frontTile: frontTile,
                leftTile: leftTile,
                rightTile: rightTile,
                leftBlocked: !leftTile.walkable,
                rightBlocked: !rightTile.walkable,
                frontBlocked: !frontTile.walkable,
                occupant: occupant(at: frontPosition),
                feature: feature(at: frontPosition)
            )
            slices.append(slice)
            if slice.frontBlocked {
                break
            }
        }

        return slices
    }

    private func advancedPosition(from start: Position, direction: Direction, steps: Int) -> Position {
        Position(
            x: start.x + (direction.delta.x * steps),
            y: start.y + (direction.delta.y * steps)
        )
    }

    private func tile(at position: Position) -> Tile {
        guard let map = state.world.maps[state.player.currentMapID],
              position.y >= 0,
              position.y < map.lines.count,
              position.x >= 0,
              position.x < map.lines[position.y].count else {
            return TileFactory.tile(for: "#")
        }

        let raw = Array(map.lines[position.y])[position.x]
        return TileFactory.tile(for: resolved(raw))
    }

    private func sideWallColor(for tile: Tile, theme: RegionTheme, brightness: Double) -> Color {
        frontWallColor(for: tile, theme: theme).opacity(max(0.28, brightness))
    }

    private func frontWallColor(for tile: Tile, theme: RegionTheme) -> Color {
        switch tile.type {
        case .floor:
            return theme.floor
        case .wall:
            return theme.wall
        case .water:
            return theme.water
        case .brush:
            return theme.brush
        case .doorLocked:
            return theme.doorLocked
        case .doorOpen:
            return theme.doorOpen
        case .shrine:
            return theme.shrine
        case .stairs:
            return theme.stairs
        case .beacon:
            return theme.beacon
        }
    }

    private func firstPersonNPCPattern(for id: String) -> [[Int]] {
        switch id {
        case "elder":
            return [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1],
                [0,1,0],
                [0,1,0]
            ]
        case "orchard_guide":
            return [
                [0,1,0],
                [1,1,0],
                [0,1,1]
            ]
        default:
            return [
                [0,1,0],
                [1,1,1],
                [0,1,0]
            ]
        }
    }

    private func firstPersonNPCColor(for id: String) -> Color {
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

    private func firstPersonEnemyPattern(for id: String) -> [[Int]] {
        if id.hasPrefix("crow") {
            return [
                [1,0,1],
                [1,1,1],
                [0,1,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,1,0],
                [1,1,1],
                [0,1,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        }
        return [
            [1,1,1],
            [1,0,1],
            [1,1,1]
        ]
    }

    private func firstPersonEnemyColor(for id: String) -> Color {
        if id.hasPrefix("crow") {
            return palette.titleGold
        }
        if id.hasPrefix("hound") {
            return palette.accentGreen
        }
        if id.hasPrefix("wraith") {
            return palette.accentViolet
        }
        return palette.titleGold
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

    var debugName: String {
        switch self {
        case .none: return "none"
        case .chest: return "chest"
        case .bed: return "bed"
        case .plateUp: return "plate_up"
        case .plateDown: return "plate_down"
        case .switchIdle: return "switch_idle"
        case .switchLit: return "switch_lit"
        case .shrine: return "shrine"
        case .beacon: return "beacon"
        case .gate: return "gate"
        }
    }
}

private struct CorridorSlice {
    let depth: Int
    let frontTile: Tile
    let leftTile: Tile
    let rightTile: Tile
    let leftBlocked: Bool
    let rightBlocked: Bool
    let frontBlocked: Bool
    let occupant: MapOccupant
    let feature: MapFeature
}

private struct PerspectiveFrame {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var width: CGFloat {
        topRight.x - topLeft.x
    }

    var height: CGFloat {
        bottomLeft.y - topLeft.y
    }

    var center: CGPoint {
        CGPoint(x: (topLeft.x + topRight.x) / 2, y: (topLeft.y + bottomLeft.y) / 2)
    }
}

enum DepthHitAxis {
    case none
    case vertical
    case horizontal
}

struct DepthRaySample {
    let column: Int
    let didHit: Bool
    let correctedDistance: Double
    let rawDistance: Double
    let maxDistance: Double
    let hitTile: Tile
    let hitAxis: DepthHitAxis
}

struct DepthBillboard {
    let id: String
    let pattern: [[Int]]
    let color: Color
    let distance: Double
    let angleOffset: Double
    let maxDistance: Double
    let scale: Double
    let widthScale: CGFloat
}

struct DepthRaycaster {
    let origin: CGPoint
    let facing: Direction
    let tileAt: (Position) -> Tile
    let fov: Double

    init(
        origin: CGPoint,
        facing: Direction,
        fov: Double = .pi / 3.1,
        tileAt: @escaping (Position) -> Tile
    ) {
        self.origin = origin
        self.facing = facing
        self.tileAt = tileAt
        self.fov = fov
    }

    func castSamples(columns: Int, maxDistance: Double) -> [DepthRaySample] {
        guard columns > 0 else { return [] }

        return (0..<columns).map { column in
            let cameraOffset = ((Double(column) + 0.5) / Double(columns)) - 0.5
            let rayAngle = baseAngle + (cameraOffset * fov)
            return castRay(column: column, angle: rayAngle, maxDistance: maxDistance)
        }
    }

    private func castRay(column: Int, angle: Double, maxDistance: Double) -> DepthRaySample {
        let originX = Double(origin.x)
        let originY = Double(origin.y)
        let rayX = cos(angle)
        let rayY = sin(angle)

        var mapX = Int(floor(originX))
        var mapY = Int(floor(originY))

        let deltaX = rayX == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / rayX)
        let deltaY = rayY == 0 ? Double.greatestFiniteMagnitude : abs(1.0 / rayY)

        let stepX: Int
        var sideX: Double
        if rayX < 0 {
            stepX = -1
            sideX = (originX - Double(mapX)) * deltaX
        } else {
            stepX = 1
            sideX = (Double(mapX + 1) - originX) * deltaX
        }

        let stepY: Int
        var sideY: Double
        if rayY < 0 {
            stepY = -1
            sideY = (originY - Double(mapY)) * deltaY
        } else {
            stepY = 1
            sideY = (Double(mapY + 1) - originY) * deltaY
        }

        var hitAxis: DepthHitAxis = .none
        var hitTile = TileFactory.tile(for: ".")
        var rawDistance = maxDistance
        var didHit = false
        var travelDistance = 0.0

        while !didHit && travelDistance < maxDistance {
            if sideX < sideY {
                mapX += stepX
                rawDistance = sideX
                sideX += deltaX
                hitAxis = .vertical
            } else {
                mapY += stepY
                rawDistance = sideY
                sideY += deltaY
                hitAxis = .horizontal
            }
            travelDistance = rawDistance

            let tile = tileAt(Position(x: mapX, y: mapY))
            if !tile.walkable {
                hitTile = tile
                didHit = true
                break
            }
        }

        if !didHit {
            return DepthRaySample(
                column: column,
                didHit: false,
                correctedDistance: maxDistance,
                rawDistance: maxDistance,
                maxDistance: maxDistance,
                hitTile: hitTile,
                hitAxis: .none
            )
        }

        let corrected = max(0.05, rawDistance * cos(angle - baseAngle))
        return DepthRaySample(
            column: column,
            didHit: true,
            correctedDistance: corrected,
            rawDistance: rawDistance,
            maxDistance: maxDistance,
            hitTile: hitTile,
            hitAxis: hitAxis
        )
    }

    private var baseAngle: Double {
        switch facing {
        case .up:
            return -.pi / 2
        case .down:
            return .pi / 2
        case .left:
            return .pi
        case .right:
            return 0
        }
    }
}

private struct CrosshairView: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let midX = proxy.size.width / 2
            let midY = proxy.size.height / 2

            Path { path in
                path.move(to: CGPoint(x: midX - 8, y: midY))
                path.addLine(to: CGPoint(x: midX + 8, y: midY))
                path.move(to: CGPoint(x: midX, y: midY - 8))
                path.addLine(to: CGPoint(x: midX, y: midY + 8))
            }
            .stroke(color, lineWidth: 1.5)
        }
    }
}

private struct LowResTileView: View {
    let tile: Tile
    let occupant: MapOccupant
    let feature: MapFeature
    let palette: UltimaPalette
    let regionTheme: RegionTheme
    let visualTheme: GraphicsVisualTheme

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
        if visualTheme == .ultima {
            return Color.black.opacity(0.25)
        }
        if tile.type == .wall {
            return Color.black.opacity(0.65)
        }
        return Color.black.opacity(0.18)
    }

    @ViewBuilder
    private func tilePattern(size: CGFloat) -> some View {
        if visualTheme == .ultima {
            ultimaTilePattern(size: size)
        } else {
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
    }

    @ViewBuilder
    private func ultimaTilePattern(size: CGFloat) -> some View {
        switch tile.type {
        case .floor:
            if Int(size).isMultiple(of: 2) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size * 0.24, height: size * 0.24)
                    .offset(x: -size * 0.20, y: -size * 0.18)
            }
        case .wall:
            VStack(spacing: max(1, size * 0.10)) {
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size, height: max(1, size * 0.08))
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: size * 0.72, height: max(1, size * 0.08))
            }
        case .water:
            HStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: size * 0.22, height: size * 0.52)
                Rectangle().fill(Color.white.opacity(0.10)).frame(width: size * 0.22, height: size * 0.34)
            }
        case .brush:
            Rectangle().fill(Color.black.opacity(0.16)).frame(width: size * 0.44, height: size * 0.44)
        case .doorLocked, .doorOpen:
            Rectangle().fill(Color.black.opacity(0.25)).frame(width: size * 0.34, height: size * 0.60)
        case .shrine, .beacon:
            Rectangle().fill(Color.white.opacity(0.14)).frame(width: size * 0.38, height: size * 0.38)
        case .stairs:
            VStack(spacing: max(1, size * 0.08)) {
                Rectangle().fill(Color.black.opacity(0.18)).frame(width: size * 0.28, height: max(1, size * 0.08))
                Rectangle().fill(Color.black.opacity(0.12)).frame(width: size * 0.54, height: max(1, size * 0.08))
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
        if visualTheme == .ultima {
            ultimaFeatureMark(size: size)
        } else {
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
    }

    @ViewBuilder
    private func ultimaFeatureMark(size: CGFloat) -> some View {
        switch feature {
        case .none:
            EmptyView()
        case .chest:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.44, height: size * 0.28)
        case .bed:
            Rectangle().fill(palette.text).frame(width: size * 0.56, height: size * 0.14)
        case .plateUp:
            Rectangle().fill(palette.accentViolet).frame(width: size * 0.40, height: size * 0.12)
        case .plateDown:
            Rectangle().fill(Color.black.opacity(0.24)).frame(width: size * 0.40, height: size * 0.12)
        case .switchIdle:
            Rectangle().fill(palette.accentBlue).frame(width: size * 0.20, height: size * 0.20)
        case .switchLit:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.20, height: size * 0.20)
        case .shrine:
            Rectangle().fill(palette.accentViolet).frame(width: size * 0.26, height: size * 0.42)
        case .beacon:
            Rectangle().fill(palette.lightGold).frame(width: size * 0.30, height: size * 0.46)
        case .gate:
            Rectangle().fill(palette.titleGold).frame(width: size * 0.24, height: size * 0.56)
        }
    }

    @ViewBuilder
    private func sprite(size: CGFloat) -> some View {
        if visualTheme == .ultima {
            switch occupant {
            case .none:
                EmptyView()
            case .player:
                simpleSprite(color: palette.text, pattern: [
                    [0,1,0],
                    [1,1,1],
                    [1,0,1]
                ], size: size * 0.62)
            case .npc(let id):
                simpleSprite(color: npcColor(for: id), pattern: ultimaNPCPattern(for: id), size: size * 0.58)
            case .enemy(let id):
                simpleSprite(color: enemyColor(for: id), pattern: ultimaEnemyPattern(for: id), size: size * 0.64)
            case .boss:
                simpleSprite(color: palette.accentViolet, pattern: [
                    [1,1,1],
                    [1,0,1],
                    [1,1,1]
                ], size: size * 0.68)
            }
        } else {
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
    }

    private func simpleSprite(color: Color, pattern: [[Int]], size: CGFloat) -> some View {
        PixelSprite(color: color, pattern: pattern)
            .frame(width: size, height: size)
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

    private func ultimaNPCPattern(for id: String) -> [[Int]] {
        switch id {
        case "elder":
            return [
                [0,1,0],
                [1,1,1],
                [1,0,1]
            ]
        case "field_scout":
            return [
                [1,0,1],
                [0,1,0],
                [0,1,0]
            ]
        case "orchard_guide":
            return [
                [0,1,0],
                [1,1,0],
                [0,1,1]
            ]
        default:
            return [
                [0,1,0],
                [1,1,1],
                [0,1,0]
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

    private func ultimaEnemyPattern(for id: String) -> [[Int]] {
        if id.hasPrefix("crow") {
            return [
                [1,0,1],
                [1,1,1],
                [0,1,0]
            ]
        }
        if id.hasPrefix("hound") {
            return [
                [1,0,0],
                [1,1,1],
                [0,0,1]
            ]
        }
        if id.hasPrefix("wraith") {
            return [
                [0,1,0],
                [1,1,1],
                [1,1,1]
            ]
        }
        return [
            [1,1,1],
            [1,0,1],
            [1,1,1]
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
    let onThemeToggle: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onCommand = onCommand
        view.onThemeToggle = onThemeToggle
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onCommand = onCommand
        nsView.onThemeToggle = onThemeToggle
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureView: NSView {
    var onCommand: ((ActionCommand) -> Void)?
    var onThemeToggle: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if isThemeToggle(event) {
            onThemeToggle?()
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
