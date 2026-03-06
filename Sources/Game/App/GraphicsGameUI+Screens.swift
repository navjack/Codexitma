#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension GameRootView {
    var titleView: some View {
        let scene = session.sceneSnapshot
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

                PixelPanel(title: "SELECTED ADVENTURE", palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.state.selectedAdventureTitle().uppercased())
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.lightGold)
                        Text(session.state.selectedAdventureSummary().uppercased())
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("A/D CHANGES THE ADVENTURE. A NEW HERO STARTS IN THE ONE SHOWN HERE.")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }

                PixelPanel(title: "MAIN MENU", palette: palette) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(scene.titleOptions, id: \.index) { option in
                            let selected = option.isSelected
                            let resolved = TitleMenuOption.allCases[option.index]

                            Button {
                                performTitleAction(resolved)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(selected ? ">" : " ")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(selected ? palette.background : palette.text)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(option.label.uppercased())
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            Spacer(minLength: 8)
                                            Text(titleOptionHint(resolved))
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        }
                                        Text(option.detail.uppercased())
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .foregroundStyle(selected ? palette.background : palette.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected ? palette.lightGold : palette.background.opacity(0.22))
                                .overlay(
                                    Rectangle()
                                        .stroke(selected ? palette.titleGold : palette.lightGold.opacity(0.45), lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }

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
                    Text("\(session.visualTheme.displayName.uppercased()) DISPLAY ACTIVE. START NEW GAME IS SELECTED BY DEFAULT.")
                    Text("W/S CHOOSE MENU OPTION   A/D CHANGE ADVENTURE")
                    Text("E OR RETURN ACTIVATE THE HIGHLIGHTED CHOICE")
                    Text("L LOADS A SAVE DIRECTLY   M OPENS EDITOR   T SWITCHES STYLE")
                    Text("F12 SAVES SCREENSHOT PNG")
                    Text("CMD/CTRL+SHIFT+D TOGGLES LIGHT DEBUG")
                    Text("Q OR X QUITS FROM THE TITLE SCREEN")
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
                Text("NEW HERO FOR \(session.state.selectedAdventureTitle().uppercased())")
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

                PixelPanel(title: "BEGIN ADVENTURE", palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("THIS HERO WILL ENTER \(session.state.selectedAdventureTitle().uppercased()).")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                menuButton("START \(session.state.selectedAdventureTitle().uppercased())") { session.send(.confirm) }
                                menuButton("BACK") { session.send(.cancel) }
                            }
                            VStack(spacing: 10) {
                                menuButton("START \(session.state.selectedAdventureTitle().uppercased())") { session.send(.confirm) }
                                menuButton("BACK") { session.send(.cancel) }
                            }
                        }
                        Text("A/D CHANGES CLASS   E OR RETURN STARTS THE ADVENTURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                    }
                    .frame(maxWidth: 540, alignment: .leading)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        menuButton("T: STYLE") { session.cycleVisualTheme() }
                        Text(session.visualTheme.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                        menuButton("M: EDIT") { requestEditor() }
                    }
                    .frame(maxWidth: 420)

                    VStack(spacing: 10) {
                        menuButton("T: STYLE") { session.cycleVisualTheme() }
                        menuButton("M: EDIT") { requestEditor() }
                        Text(session.visualTheme.displayName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accentBlue)
                    }
                    .frame(maxWidth: 320)
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
