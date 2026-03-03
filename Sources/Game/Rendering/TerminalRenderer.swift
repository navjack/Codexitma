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
            return titleFrame(state: state)
        case .characterCreation:
            return characterCreationFrame(state: state)
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

    private func titleFrame(state: GameState) -> ScreenBuffer {
        var buffer = ScreenBuffer()
        let title = state.selectedAdventureTitle().uppercased()
        buffer.write(title, color: .yellow, x: 28, y: 3)
        buffer.write("A Swift terminal RPG", color: .cyan, x: 29, y: 5)
        buffer.write(state.selectedAdventureSummary(), x: 8, y: 7, maxWidth: 64)
        buffer.write("A/D or arrows: choose adventure", color: .brightBlack, x: 23, y: 8)
        buffer.write("N  Create Hero", x: 27, y: 9)
        buffer.write("L  Load Game", x: 29, y: 10)
        buffer.write("X  Quit", x: 29, y: 11)
        buffer.write("Character creator: classes, skills, traits, and starting gear.", x: 6, y: 15)
        buffer.write("WASD/Arrows move. E act. I open pack. J hint.", x: 11, y: 17)
        buffer.write("K save, L load, X quit. --bridge for JSON control.", x: 9, y: 18)
        buffer.write("Expect an 80x24 terminal for the full retro frame.", color: .brightBlack, x: 14, y: 19)
        return buffer
    }

    private func characterCreationFrame(state: GameState) -> ScreenBuffer {
        var buffer = ScreenBuffer()
        let heroClass = state.selectedHeroClass()
        let template = heroTemplate(for: heroClass)
        buffer.write("CREATE YOUR HERO", color: .yellow, x: 29, y: 2)
        buffer.write(state.selectedAdventureTitle().uppercased(), color: .magenta, x: 22, y: 3, maxWidth: 36)
        buffer.write(template.title, color: .cyan, x: 24, y: 5, maxWidth: 32)
        buffer.write(template.summary, x: 9, y: 7, maxWidth: 62)
        buffer.write("< A / LEFT        D / RIGHT >", color: .brightBlack, x: 24, y: 9)
        buffer.write("E Confirm   Q Back   J Details", color: .brightBlack, x: 24, y: 10)

        for (index, stat) in TraitStat.allCases.enumerated() {
            let value = template.traits.value(for: stat)
            buffer.write("\(stat.shortLabel): \(value)", x: 17 + (index % 3) * 16, y: 13 + (index / 3))
        }

        buffer.write("Skills", color: .yellow, x: 18, y: 17)
        for (index, skill) in template.skills.enumerated() {
            buffer.write(skill.displayName, x: 18 + (index * 18), y: 18, maxWidth: 16)
        }
        buffer.write("Start Gear", color: .yellow, x: 18, y: 20)
        buffer.write("W \(shortName(template.startingEquipment.weapon.flatMap { itemTable[$0]?.name } ?? "None"))", x: 18, y: 21, maxWidth: 18)
        buffer.write("A \(shortName(template.startingEquipment.armor.flatMap { itemTable[$0]?.name } ?? "None"))", x: 38, y: 21, maxWidth: 18)
        buffer.write("C \(shortName(template.startingEquipment.charm.flatMap { itemTable[$0]?.name } ?? "None"))", x: 58, y: 21, maxWidth: 18)
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
        for interactable in map.interactables {
            guard let marker = overlayMarker(for: interactable, opened: state.world.openedInteractables) else { continue }
            buffer.put(marker.glyph, color: marker.color, x: interactable.position.x + 1, y: interactable.position.y + 1)
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
        buffer.write(state.player.heroClass.displayName, color: .cyan, x: x, y: 2, maxWidth: 17)
        buffer.write("HP \(state.player.health)/\(state.player.maxHealth)", x: x, y: 3)
        buffer.write("ST \(state.player.stamina)/\(state.player.maxStamina)", x: x, y: 4)
        buffer.write("LN \(state.player.effectiveLanternCapacity())", x: x, y: 5)
        buffer.write("AT \(state.player.effectiveAttack()) DF \(state.player.effectiveDefense())", x: x, y: 6, maxWidth: 17)
        buffer.write("MK \(state.player.marks)", x: x, y: 7)
        if let map = state.world.maps[state.player.currentMapID] {
            buffer.write(map.name, color: .cyan, x: x, y: 8, maxWidth: 17)
        }
        buffer.write("Goal:", color: .yellow, x: x, y: 10)
        let objective = QuestSystem.objective(for: state.quests, flow: state.questFlow)
        buffer.write(objective, x: x, y: 11, maxWidth: 17)
        let keyCount = state.player.inventory.filter { $0.kind == .key || $0.kind == .quest }.count
        buffer.write("Keys \(keyCount)", x: x, y: 13)
        buffer.write("Bag \(state.player.inventory.count)/\(state.player.inventoryCapacity())", x: x, y: 14)
        buffer.write("Log", color: .yellow, x: 2, y: 23)
        let lines = Array(state.messages.suffix(1))
        for (index, message) in lines.enumerated() {
            buffer.write(message, x: 7, y: 23 + index, maxWidth: 72)
        }
        if state.mode == .inventory {
            buffer.write("Inventory", color: .yellow, x: x, y: 15)
            let start = scrollingStartIndex(
                selection: state.inventorySelectionIndex,
                total: state.player.inventory.count,
                windowSize: 5
            )
            let visible = state.player.inventory.dropFirst(start).prefix(5)
            for (offset, item) in visible.enumerated() {
                let actualIndex = start + offset
                let marker: Character = actualIndex == state.inventorySelectionIndex ? ">" : " "
                let color: ANSIColor = actualIndex == state.inventorySelectionIndex ? .yellow : .reset
                buffer.write("\(marker)\(item.name)", color: color, x: x, y: 16 + offset, maxWidth: 17)
            }
            if start > 0 {
                buffer.put("^", color: .brightBlack, x: x + 16, y: 15)
            }
            if start + 5 < state.player.inventory.count {
                buffer.put("v", color: .brightBlack, x: x + 16, y: 21)
            }
            buffer.write("E Use R Drop", color: .brightBlack, x: x, y: 21, maxWidth: 17)
        } else if state.mode == .shop {
            buffer.write(state.shopTitle ?? "Store", color: .yellow, x: x, y: 15, maxWidth: 17)
            for (offset, line) in state.shopLines.prefix(2).enumerated() {
                buffer.write(line, x: x, y: 16 + offset, maxWidth: 17)
            }
            if let detail = state.shopDetail {
                buffer.write(detail, color: .brightBlack, x: x, y: 18, maxWidth: 17)
            }
            buffer.write("E Buy  Q Leave", color: .brightBlack, x: x, y: 20, maxWidth: 17)
            buffer.write("W/S Pick J Info", color: .brightBlack, x: x, y: 21, maxWidth: 17)
        } else if state.mode == .dialogue, let dialogue = state.currentDialogue {
            buffer.write(dialogue.speaker, color: .yellow, x: x, y: 15, maxWidth: 17)
            for (index, line) in dialogue.lines.prefix(4).enumerated() {
                buffer.write(line, x: x, y: 16 + index, maxWidth: 17)
            }
        }
        if state.mode == .shop {
            let offers = Array(state.shopOffers.prefix(4))
            for (offset, offer) in offers.enumerated() {
                let marker = offset == state.shopSelectionIndex ? ">" : " "
                let itemName = itemTable[offer.itemID]?.name ?? offer.itemID.rawValue
                let soldOut = !offer.repeatable && state.world.purchasedShopOffers.contains(offer.id)
                let status = soldOut ? " SOLD" : " \(offer.price)M"
                buffer.write("\(marker)\(shortShopName(itemName, suffix: status))", x: 2, y: 18 + offset, maxWidth: 56)
            }
        }
        if state.mode != .inventory && state.mode != .dialogue && state.mode != .shop {
            buffer.write("W \(shortName(state.player.equippedName(for: .weapon)))", color: .brightBlack, x: x, y: 15, maxWidth: 17)
            buffer.write("A \(shortName(state.player.equippedName(for: .armor)))", color: .brightBlack, x: x, y: 16, maxWidth: 17)
            buffer.write("C \(shortName(state.player.equippedName(for: .charm)))", color: .brightBlack, x: x, y: 17, maxWidth: 17)
            buffer.write("TR \(state.player.traitSummaryLine())", color: .brightBlack, x: x, y: 18, maxWidth: 17)
            buffer.write("E Act  I Pack", color: .brightBlack, x: x, y: 19, maxWidth: 17)
            buffer.write("J Hint K Save", color: .brightBlack, x: x, y: 20, maxWidth: 17)
            buffer.write("L Load X Quit", color: .brightBlack, x: x, y: 21, maxWidth: 17)
        }
    }

    private func shortName(_ value: String) -> String {
        String(value.prefix(15))
    }

    private func shortShopName(_ value: String, suffix: String) -> String {
        let trimmed = String(value.prefix(max(1, 16 - suffix.count)))
        return trimmed + suffix
    }

    private func scrollingStartIndex(selection: Int, total: Int, windowSize: Int) -> Int {
        guard total > windowSize else { return 0 }
        let centered = selection - (windowSize / 2)
        return max(0, min(centered, total - windowSize))
    }

    private func overlayMarker(for interactable: InteractableDefinition, opened: Set<String>) -> (glyph: Character, color: ANSIColor)? {
        switch interactable.kind {
        case .chest:
            if opened.contains(interactable.id) { return nil }
            return ("$", .yellow)
        case .bed:
            return ("=", .white)
        case .gate:
            return ("+", .yellow)
        case .plate:
            return ("^", opened.contains(interactable.id) ? .brightBlack : .magenta)
        case .switchRune:
            return ("o", opened.contains("spire_mirrors_aligned") ? .yellow : .cyan)
        case .shrine:
            return ("*", .cyan)
        case .beacon:
            return ("B", .yellow)
        case .npc:
            return nil
        }
    }
}
