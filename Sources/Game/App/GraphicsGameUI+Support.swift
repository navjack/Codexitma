#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI

extension GameRootView {
    func handleMove(_ direction: MoveCommandDirection) {
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

    var currentMapName: String {
        session.state.world.maps[session.state.player.currentMapID]?.name ?? "UNKNOWN"
    }

    func itemColor(_ item: Item) -> Color {
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

    var mapPanelTitle: String {
        switch session.visualTheme {
        case .gemstone:
            return "\(currentMapName.uppercased()) CHAMBER"
        case .ultima:
            return "\(currentMapName.uppercased()) OVERWORLD"
        case .depth3D:
            return "\(currentMapName.uppercased()) DEPTH"
        }
    }

    var movementHintLine: String {
        if session.state.mode == .pause {
            return "W/S OR A/D MENU"
        }
        if session.state.mode == .shop || session.state.mode == .inventory {
            return "ARROWS/WASD BROWSE"
        }
        if session.visualTheme == .depth3D {
            return "W/UP FWD  S/DN BACK"
        }
        return "ARROWS/WASD MOVE"
    }

    var starfieldColor: Color {
        switch session.visualTheme {
        case .gemstone:
            return palette.accentBlue
        case .ultima:
            return palette.accentGreen
        case .depth3D:
            return palette.accentViolet
        }
    }

    var visibleInventoryRows: [(index: Int, item: Item)] {
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

    var selectedInventoryItem: Item? {
        guard !session.state.player.inventory.isEmpty else { return nil }
        let index = max(0, min(session.state.inventorySelectionIndex, session.state.player.inventory.count - 1))
        return session.state.player.inventory[index]
    }

    var inputPrimaryLine: String {
        switch session.state.mode {
        case .pause:
            return "E CHOOSE  Q RESUME  K SAVE"
        case .shop:
            return "E BUY   J INFO   Q LEAVE"
        case .inventory:
            return "E USE   R DROP   Q LEAVE"
        default:
            if session.visualTheme == .depth3D {
                return "A/D TURN  E ACT  I PACK"
            }
            return "E ACT   I PACK   Q MENU"
        }
    }

    var inputSecondaryLine: String {
        switch session.state.mode {
        case .pause:
            return "SAVE+TITLE / TITLE / QUIT"
        case .shop:
            return "K SAVE  L LOAD  X QUIT"
        case .inventory:
            return "J INFO  K SAVE  L LOAD"
        default:
            return "J GOAL  K SAVE  L LOAD"
        }
    }

    var inputTertiaryLine: String {
        switch session.state.mode {
        case .pause:
            return "M EDIT  T STYLE  X QUIT"
        case .shop:
            return "T STYLE  I ALSO LEAVES"
        case .inventory:
            return "T STYLE  I ALSO LEAVES"
        default:
            if session.visualTheme == .depth3D {
                return "Q MENU  M EDIT  X QUIT"
            }
            return "T STYLE  M EDIT  X QUIT"
        }
    }

    var inputQuaternaryLine: String {
        "F12 SAVES SCREENSHOT PNG"
    }

    var inputQuinaryLine: String {
        "CMD/CTRL+SHIFT+D DEBUG"
    }

    func performTitleAction(_ option: TitleMenuOption) {
        switch option {
        case .startNewGame:
            session.send(.confirm)
        case .loadSave:
            session.send(.load)
        case .quitGame:
            session.send(.quit)
        }
    }

    func titleOptionHint(_ option: TitleMenuOption) -> String {
        switch option {
        case .startNewGame:
            return "E / RETURN"
        case .loadSave:
            return "L"
        case .quitGame:
            return "X / Q"
        }
    }

    var editorConfirmOverlay: some View {
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

    var pauseOverlay: some View {
        let options = PauseMenuOption.allCases

        return ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            PixelPanel(title: "LEAVE ROAD?", palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("YOU CAN RETURN TO THE TITLE SCREEN TO LOAD A DIFFERENT ADVENTURE.")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("CHOOSE WHETHER TO RESUME, SAVE, OR STEP BACK TO TITLE.")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            let selected = index == session.state.pauseSelectionIndex
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(selected ? ">" : " ")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(selected ? palette.background : palette.text)
                                    Text(option.label.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundStyle(selected ? palette.background : palette.lightGold)
                                }

                                Text(option.detail.uppercased())
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(selected ? palette.background.opacity(0.92) : palette.text.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 16)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(selected ? palette.lightGold : .clear)
                        }
                    }

                    Text("W/S OR A/D MOVE   E SELECT   Q RESUME   K SAVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.lightGold)
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .frame(maxWidth: 580)
        }
    }

    func requestEditor() {
        guard session.canOpenEditorFromCurrentMode() else { return }
        showingEditorConfirm = true
    }

    func captureScreenshot() {
        let label = screenshotLabel
        do {
            let url = try NativeScreenshotCapture.captureKeyWindow(label: label)
            postScreenshotNotice("SHOT SAVED \(url.lastPathComponent.uppercased())")
        } catch {
            postScreenshotNotice("SHOT FAILED \(error.localizedDescription.uppercased())")
        }
    }

    var screenshotLabel: String {
        ScreenshotSupport.defaultGameLabel(for: session.state)
    }

    func postScreenshotNotice(_ text: String) {
        screenshotNoticeWorkItem?.cancel()
        screenshotNotice = text
        let workItem = DispatchWorkItem {
            screenshotNotice = nil
        }
        screenshotNoticeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
    }

    func toggleDebugOverlay() {
        showDebugLightingOverlay.toggle()
        let state = showDebugLightingOverlay ? "ON" : "OFF"
        postScreenshotNotice("LIGHT DEBUG \(state)")
    }
}
#endif
