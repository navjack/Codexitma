#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension GameRootView {
    var titleView: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                    Text("M OPENS EDITOR   F12 SAVES SCREENSHOT PNG")
                    Text("CMD/CTRL+SHIFT+D TOGGLES LIGHT DEBUG")
                    Text("Q BACKS OUT OF MENUS")
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

    var creatorView: some View {
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

    var endingView: some View {
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

    var worldView: some View {
        GeometryReader { proxy in
            let availableSize = CGSize(
                width: max(320, proxy.size.width - (WorldDashboardLayoutMetrics.outerPadding * 2)),
                height: max(320, proxy.size.height - (WorldDashboardLayoutMetrics.outerPadding * 2))
            )
            let useWideLayout = availableSize.width >= WorldDashboardLayoutMetrics.wideLayoutMinimumWidth
                && availableSize.height >= WorldDashboardLayoutMetrics.wideLayoutMinimumHeight

            FittedDashboardView(
                availableSize: availableSize,
                maxScale: WorldDashboardLayoutMetrics.maximumScale
            ) {
                if useWideLayout {
                    wideWorldDashboard(availableHeight: availableSize.height)
                } else {
                    compactWorldDashboard
                }
            }
            .padding(WorldDashboardLayoutMetrics.outerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    func wideWorldDashboard(availableHeight: CGFloat) -> some View {
        let sidebarPanelWidth = WorldDashboardLayoutMetrics.sidebarPanelWidth

        return HStack(alignment: .top, spacing: WorldDashboardLayoutMetrics.columnSpacing) {
            primaryWorldColumn(expandedLog: true)
                .frame(width: WorldDashboardLayoutMetrics.primaryColumnWidth, alignment: .leading)
                .frame(minHeight: availableHeight, alignment: .topLeading)

            VStack(alignment: .leading, spacing: WorldDashboardLayoutMetrics.panelSpacing) {
                HStack(alignment: .top, spacing: WorldDashboardLayoutMetrics.panelSpacing) {
                    statusPanel
                        .frame(width: sidebarPanelWidth)
                    commercePanel
                        .frame(width: sidebarPanelWidth)
                }

                HStack(alignment: .top, spacing: WorldDashboardLayoutMetrics.panelSpacing) {
                    paperDollPanel
                        .frame(width: sidebarPanelWidth)
                    inputPanel
                        .frame(width: sidebarPanelWidth)
                }

                HStack(alignment: .top, spacing: WorldDashboardLayoutMetrics.panelSpacing) {
                    legendPanel
                        .frame(width: sidebarPanelWidth)
                    traitsPanel
                        .frame(width: sidebarPanelWidth)
                }
            }
            .frame(width: (sidebarPanelWidth * 2) + WorldDashboardLayoutMetrics.panelSpacing, alignment: .leading)
        }
    }

    var compactWorldDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            primaryWorldColumn(expandedLog: false)
                .frame(width: WorldDashboardLayoutMetrics.primaryColumnWidth, alignment: .leading)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: WorldDashboardLayoutMetrics.panelSpacing),
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: WorldDashboardLayoutMetrics.panelSpacing)
                ],
                alignment: .leading,
                spacing: WorldDashboardLayoutMetrics.panelSpacing
            ) {
                statusPanel
                commercePanel
                paperDollPanel
                inputPanel
                legendPanel
                traitsPanel
            }
            .frame(width: WorldDashboardLayoutMetrics.primaryColumnWidth, alignment: .leading)
        }
    }

    func primaryWorldColumn(expandedLog: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PixelPanel(title: mapPanelTitle, palette: palette) {
                MapBoardView(
                    state: session.state,
                    scene: session.sceneSnapshot,
                    palette: palette,
                    visualTheme: session.visualTheme,
                    showLightingDebug: showDebugLightingOverlay
                )
            }

            if expandedLog {
                PixelPanel(title: "LOG", palette: palette) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(session.state.messages.suffix(10).enumerated()), id: \.offset) { _, line in
                            Text(line.uppercased())
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
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
    }
}
#endif
