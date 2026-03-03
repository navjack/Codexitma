import Foundation

enum TileFactory {
    static func isAllowedGlyph(_ char: Character) -> Bool {
        switch char {
        case ".", "#", "~", "\"", "+", "/", "*", ">", "B", " ":
            return true
        default:
            return false
        }
    }

    static func tile(for char: Character) -> Tile {
        switch char {
        case "#":
            return Tile(type: .wall, glyph: "#", walkable: false, color: .brightBlack)
        case "~":
            return Tile(type: .water, glyph: "~", walkable: false, color: .blue)
        case "\"":
            return Tile(type: .brush, glyph: "\"", walkable: true, color: .green)
        case "+":
            return Tile(type: .doorLocked, glyph: "+", walkable: false, color: .yellow)
        case "/":
            return Tile(type: .doorOpen, glyph: "/", walkable: true, color: .yellow)
        case "*":
            return Tile(type: .shrine, glyph: "*", walkable: true, color: .cyan)
        case ">":
            return Tile(type: .stairs, glyph: ">", walkable: true, color: .white)
        case "B":
            return Tile(type: .beacon, glyph: "B", walkable: true, color: .yellow)
        default:
            return Tile(type: .floor, glyph: ".", walkable: true, color: .reset)
        }
    }
}
