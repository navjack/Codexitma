#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

@MainActor
struct GameRootView: View {
    @ObservedObject var session: GameSessionController
    @State private var showingEditorConfirm = false

    private let palette = UltimaPalette()

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            PixelStars(color: starfieldColor).ignoresSafeArea()
            PixelKeyCapture(
                onCommand: {
                    guard !showingEditorConfirm else { return }
                    session.send($0)
                },
                onThemeToggle: {
                    guard !showingEditorConfirm else { return }
                    session.cycleVisualTheme()
                },
                onEditorRequest: {
                    guard !showingEditorConfirm else { return }
                    requestEditor()
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if showingEditorConfirm {
                editorConfirmOverlay
            }
        }
        .onMoveCommand(perform: handleMove)
    }

    private var titleView: some View {
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Spacer(minLength: 24)
                PixelBanner(text: "CODEXITMA", color: palette.titleGold)
                Text("A LOW-RES APPLE II FANTASY")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text("\(session.state.selectedAdventureTitle().uppercased()) // CLASSES, TRAITS, AND LOW-RES LEGENDS")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.accentBlue)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        menuButton("A: PREV") { session.send(.move(.left)) }
                        menuButton("D: NEXT") { session.send(.move(.right)) }
                        menuButton("N: CREATE") { session.send(.newGame) }
                        menuButton("L: LOAD") { session.send(.load) }
                        menuButton("M: EDIT") { requestEditor() }
                        menuButton("X: QUIT") { session.send(.quit) }
                    }
                    .frame(maxWidth: 900)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            menuButton("A: PREV") { session.send(.move(.left)) }
                            menuButton("D: NEXT") { session.send(.move(.right)) }
                            menuButton("N: CREATE") { session.send(.newGame) }
                        }
                        HStack(spacing: 10) {
                            menuButton("L: LOAD") { session.send(.load) }
                            menuButton("M: EDIT") { requestEditor() }
                            menuButton("X: QUIT") { session.send(.quit) }
                        }
                    }
                    .frame(maxWidth: 540)
                }

                Text(session.state.selectedAdventureSummary().uppercased())
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 820)

                ViewThatFits(in: .horizontal) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        menuButton("T: STYLE") { session.cycleVisualTheme() }
                            .frame(maxWidth: 220)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DISPLAY \(session.visualTheme.displayName.uppercased())")
                            Text(session.visualTheme.summary.uppercased())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.9))
                    }
                    .frame(maxWidth: 540, alignment: .leading)
                }

                VStack(spacing: 4) {
                    Text("\(session.visualTheme.displayName.uppercased()) DISPLAY ACTIVE. CREATE A HERO BEFORE YOU ENTER THE VALLEY")
                    Text("A/D PICK ADVENTURE   ARROWS/WASD STEP ROOM TO ROOM")
                    Text("E TALK OR USE   I OPEN PACK")
                    Text("J SHOW GOAL   K SAVE   L LOAD   T SWITCH STYLE")
                    Text("M OPENS EDITOR   Q BACKS OUT OF MENUS")
                    Text("--BRIDGE / --SCRIPT FOR HEADLESS CONTROL")
                }
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.text.opacity(0.85))
                Spacer(minLength: 24)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var creatorView: some View {
        let heroClass = session.state.selectedHeroClass()
        let template = heroTemplate(for: heroClass)

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Spacer(minLength: 24)
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
                .frame(maxWidth: 360)

                PixelPanel(title: "TRAITS", palette: palette) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(TraitStat.allCases, id: \.self) { stat in
                            Text("\(stat.shortLabel) \(template.traits.value(for: stat))  \(stat.displayName.uppercased())")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text)
                        }
                    }
                    .frame(maxWidth: 320, alignment: .leading)
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
                    .frame(maxWidth: 520, alignment: .leading)
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
                    .frame(maxWidth: 520, alignment: .leading)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        menuButton("T: STYLE") { session.cycleVisualTheme() }
                        Text(session.visualTheme.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                        menuButton("M: EDIT") { requestEditor() }
                        menuButton("E: BEGIN") { session.send(.confirm) }
                        menuButton("Q: BACK") { session.send(.cancel) }
                    }
                    .frame(maxWidth: 520)

                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            menuButton("T: STYLE") { session.cycleVisualTheme() }
                            menuButton("M: EDIT") { requestEditor() }
                        }
                        HStack(spacing: 10) {
                            menuButton("E: BEGIN") { session.send(.confirm) }
                            menuButton("Q: BACK") { session.send(.cancel) }
                        }
                        Text(session.visualTheme.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                    }
                    .frame(maxWidth: 420)
                }
                Spacer(minLength: 24)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var endingView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Spacer(minLength: 24)
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
                Spacer(minLength: 24)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private var worldView: some View {
        let sidebarPanelWidth: CGFloat = 192

        return GeometryReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        primaryWorldColumn
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

                    VStack(alignment: .leading, spacing: 14) {
                        primaryWorldColumn

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            statusPanel
                            commercePanel
                            paperDollPanel
                            inputPanel
                            legendPanel
                            traitsPanel
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                }
                .padding(18)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private var primaryWorldColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelPanel(title: mapPanelTitle, palette: palette) {
                MapBoardView(
                    state: session.state,
                    scene: session.sceneSnapshot,
                    palette: palette,
                    visualTheme: session.visualTheme
                )
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
                    HStack(spacing: 8) {
                        menuButton("M") { requestEditor() }
                        menuButton("T") { session.cycleVisualTheme() }
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
        guard !showingEditorConfirm else { return }
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
                return "Q BACK  M EDIT  X QUIT"
            }
            return "T STYLE  M EDIT  X QUIT"
        }
    }

    private var editorConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.74)
                .ignoresSafeArea()

            PixelPanel(title: "OPEN EDITOR?", palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(session.editorConfirmationLines().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("ARE YOU SURE?")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)

                    HStack(spacing: 10) {
                        menuButton("YES OPEN") {
                            showingEditorConfirm = false
                            session.openEditorForCurrentContext()
                        }
                        menuButton("NO STAY") {
                            showingEditorConfirm = false
                        }
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .frame(maxWidth: 580)
        }
    }

    private func requestEditor() {
        guard session.canOpenEditorFromCurrentMode() else { return }
        showingEditorConfirm = true
    }
}
#endif
