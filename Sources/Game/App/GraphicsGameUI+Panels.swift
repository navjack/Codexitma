#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension GameRootView {
    var statusPanel: some View {
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

    var commercePanel: some View {
        Group {
            if session.state.mode == .shop {
                shopPanel
            } else {
                packPanel
            }
        }
    }

    var packPanel: some View {
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

    var shopPanel: some View {
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

    var paperDollPanel: some View {
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

    var inputPanel: some View {
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
                Text(inputQuaternaryLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(inputQuinaryLine)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.text)

                VStack(spacing: 8) {
                    if session.state.mode == .pause {
                        HStack(spacing: 8) {
                            menuButton("UP") { session.send(.move(.up)) }
                            menuButton("DOWN") { session.send(.move(.down)) }
                            menuButton("E") { session.send(.confirm) }
                        }
                        HStack(spacing: 8) {
                            menuButton("Q") { session.send(.cancel) }
                            menuButton("K") { session.send(.save) }
                            menuButton("X") { session.send(.quit) }
                        }
                        HStack(spacing: 8) {
                            menuButton("T") { session.cycleVisualTheme() }
                            menuButton("M") { requestEditor() }
                            menuButton("SHOT") { captureScreenshot() }
                        }
                    } else {
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
                            menuButton("SHOT") { captureScreenshot() }
                        }
                    }
                }
            }
        }
    }

    var legendPanel: some View {
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

    var traitsPanel: some View {
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

    func stat(_ label: String, _ value: String) -> some View {
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

    func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
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

    func legendRow(color: Color, label: String) -> some View {
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

    func equipmentRow(_ slot: String, _ value: String) -> some View {
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
}
#endif
