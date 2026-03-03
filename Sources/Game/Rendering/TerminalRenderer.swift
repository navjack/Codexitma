import Darwin
import Foundation

final class TerminalRenderer {
    let expectedWidth = 80
    let expectedHeight = 24
    let isInteractive: Bool
    let useColor: Bool

    init() {
        isInteractive = isatty(STDOUT_FILENO) == 1
        useColor = ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    func prepare() {
        guard isInteractive else { return }
        print("\u{001B}[?25l\u{001B}[2J", terminator: "")
        fflush(stdout)
    }

    func restore() {
        guard isInteractive else { return }
        print("\u{001B}[0m\u{001B}[?25h", terminator: "")
        fflush(stdout)
    }

    func makeFrame(for state: GameState) -> ScreenBuffer {
        switch state.mode {
        case .title:
            return titleFrame()
        case .ending:
            return endingFrame(state: state)
        default:
            return worldFrame(state: state)
        }
    }

    func makeShutdownFrame(message: String) -> ScreenBuffer {
        var buffer = ScreenBuffer()
        buffer.write(message, color: .yellow, x: 2, y: 2)
        return buffer
    }

    func render(_ buffer: ScreenBuffer) {
        let output = renderString(buffer)
        if isInteractive {
            print("\u{001B}[H\(output)", terminator: "")
        } else {
            print(output)
        }
        fflush(stdout)
    }

    func renderString(_ buffer: ScreenBuffer) -> String {
        var out = ""
        for y in 0..<buffer.height {
            var currentColor: ANSIColor = .reset
            for x in 0..<buffer.width {
                let cell = buffer.cells[(y * buffer.width) + x]
                if useColor, cell.color != currentColor {
                    out += "\u{001B}[\(cell.color.foregroundCode)m"
                    currentColor = cell.color
                }
                out.append(cell.character)
            }
            if useColor, currentColor != .reset {
                out += "\u{001B}[0m"
            }
            if y < buffer.height - 1 {
                out.append("\n")
            }
        }
        return out
    }

    private func titleFrame() -> ScreenBuffer {
        var buffer = ScreenBuffer()
        let title = "ASHES OF MERROW"
        buffer.write(title, color: .yellow, x: 28, y: 3)
        buffer.write("A Swift terminal RPG", color: .cyan, x: 29, y: 5)
        buffer.write("N  New Game", x: 29, y: 9)
        buffer.write("L  Load Game", x: 29, y: 10)
        buffer.write("X  Quit", x: 29, y: 11)
        buffer.write("Use WASD or arrows. E to interact. I for inventory.", x: 12, y: 16)
        buffer.write("Expect an 80x24 terminal for the full retro frame.", color: .brightBlack, x: 14, y: 18)
        return buffer
    }

    private func endingFrame(state: GameState) -> ScreenBuffer {
        var buffer = ScreenBuffer()
        buffer.write("THE BEACON BURNS AGAIN", color: .yellow, x: 25, y: 4)
        buffer.write("The valley exhales. Merrow wakes beneath a clean dawn.", x: 10, y: 8)
        buffer.write("You carried the old flame through ash and shadow.", x: 14, y: 10)
        if let last = state.messages.last {
            buffer.write(last, color: .cyan, x: 8, y: 14, maxWidth: 64)
        }
        buffer.write("Press X to leave the valley.", x: 26, y: 18)
        return buffer
    }

    private func worldFrame(state: GameState) -> ScreenBuffer {
        var buffer = ScreenBuffer()
        drawChrome(into: &buffer)
        drawWorld(into: &buffer, state: state)
        drawHUD(into: &buffer, state: state)
        return buffer
    }

    private func drawChrome(into buffer: inout ScreenBuffer) {
        for y in 0..<22 {
            buffer.put("|", color: .brightBlack, x: 60, y: y)
        }
        for x in 0..<80 {
            buffer.put("-", color: .brightBlack, x: x, y: 22)
        }
    }

    private func drawWorld(into buffer: inout ScreenBuffer, state: GameState) {
        guard let map = state.world.maps[state.player.currentMapID] else { return }
        for (y, line) in map.lines.enumerated() {
            for (x, char) in line.enumerated() {
                let tile = TileFactory.tile(for: char)
                buffer.put(tile.glyph, color: tile.color, x: x + 1, y: y + 1)
            }
        }
        for npc in state.world.npcs where npc.mapID == state.player.currentMapID && npc.position != state.player.position {
            buffer.put(npc.glyph, color: npc.color, x: npc.position.x + 1, y: npc.position.y + 1)
        }
        for enemy in state.world.enemies where enemy.mapID == state.player.currentMapID && enemy.active {
            buffer.put(enemy.glyph, color: enemy.color, x: enemy.position.x + 1, y: enemy.position.y + 1)
        }
        buffer.put("@", color: .white, x: state.player.position.x + 1, y: state.player.position.y + 1)
    }

    private func drawHUD(into buffer: inout ScreenBuffer, state: GameState) {
        let x = 62
        buffer.write(state.player.name, color: .yellow, x: x, y: 1, maxWidth: 17)
        buffer.write("HP \(state.player.health)/\(state.player.maxHealth)", x: x, y: 3)
        buffer.write("ST \(state.player.stamina)/\(state.player.maxStamina)", x: x, y: 4)
        buffer.write("LN \(state.player.lanternCharge)", x: x, y: 5)
        if let map = state.world.maps[state.player.currentMapID] {
            buffer.write(map.name, color: .cyan, x: x, y: 7, maxWidth: 17)
        }
        buffer.write("Goal:", color: .yellow, x: x, y: 9)
        let objective = QuestSystem.objective(for: state.quests)
        buffer.write(objective, x: x, y: 10, maxWidth: 17)
        let keyCount = state.player.inventory.filter { $0.kind == .key || $0.kind == .quest }.count
        buffer.write("Keys \(keyCount)", x: x, y: 13)
        buffer.write("Bag \(state.player.inventory.count)/8", x: x, y: 14)
        buffer.write("Log", color: .yellow, x: 2, y: 23)
        let lines = Array(state.messages.suffix(1))
        for (index, message) in lines.enumerated() {
            buffer.write(message, x: 7, y: 23 + index, maxWidth: 72)
        }
        if state.mode == .inventory {
            buffer.write("Inventory", color: .yellow, x: x, y: 16)
            for (index, item) in state.player.inventory.prefix(5).enumerated() {
                buffer.write(item.name, x: x, y: 17 + index, maxWidth: 17)
            }
        }
        if state.mode == .dialogue, let dialogue = state.currentDialogue {
            buffer.write(dialogue.speaker, color: .yellow, x: x, y: 16, maxWidth: 17)
            for (index, line) in dialogue.lines.prefix(4).enumerated() {
                buffer.write(line, x: x, y: 17 + index, maxWidth: 17)
            }
        }
    }
}
