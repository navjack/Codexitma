import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case terrain
    case npc
    case enemy
    case interactable
    case portal
    case spawn
    case erase
    case select

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .terrain: return "TERR"
        case .npc: return "NPC"
        case .enemy: return "ENM"
        case .interactable: return "INT"
        case .portal: return "PORT"
        case .spawn: return "SPAWN"
        case .erase: return "ERASE"
        case .select: return "SEL"
        }
    }

    var title: String {
        switch self {
        case .terrain: return "Terrain"
        case .npc: return "NPC"
        case .enemy: return "Enemy"
        case .interactable: return "Interactable"
        case .portal: return "Portal"
        case .spawn: return "Spawn"
        case .erase: return "Erase"
        case .select: return "Select"
        }
    }

    var helpText: String {
        switch self {
        case .terrain:
            return "Paint terrain onto the tile layer."
        case .npc:
            return "Place layered NPC records and auto-seed a stub dialogue."
        case .enemy:
            return "Place layered enemies on top of the terrain."
        case .interactable:
            return "Place a coordinate-based interactable record."
        case .portal:
            return "Place a portal that links to the next map's spawn."
        case .spawn:
            return "Move the active map's player spawn point."
        case .erase:
            return "Remove a placed object, or clear a tile back to floor."
        case .select:
            return "Inspect what already exists at a coordinate."
        }
    }
}

enum EditorContentTab: String, CaseIterable, Identifiable {
    case maps
    case dialogues
    case questFlow
    case encounters
    case shops
    case npcs
    case enemies

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .maps: return "MAPS"
        case .dialogues: return "DIALOG"
        case .questFlow: return "QUEST"
        case .encounters: return "ENCOUN"
        case .shops: return "SHOPS"
        case .npcs: return "NPCS"
        case .enemies: return "ENEMIES"
        }
    }

    var title: String {
        switch self {
        case .maps: return "Maps"
        case .dialogues: return "Dialogues"
        case .questFlow: return "Quest Flow"
        case .encounters: return "Encounters"
        case .shops: return "Shops"
        case .npcs: return "NPC Roster"
        case .enemies: return "Enemy Roster"
        }
    }
}

enum EditorSelectionKind: Equatable {
    case tile
    case spawn
    case npc(id: String)
    case enemy(id: String)
    case interactable(id: String)
    case portal(index: Int)
}

struct EditorCanvasSelection: Equatable {
    let kind: EditorSelectionKind
    let position: Position
}

enum EditorCanvasOverlayStyle: Equatable {
    case ansi(ANSIColor)
    case interactable(InteractableKind)
    case portal
    case spawn
}

struct EditorCanvasOverlay {
    let glyph: String
    let style: EditorCanvasOverlayStyle
}

extension InteractableKind {
    var editorTitle: String {
        switch self {
        case .npc:
            return "Waystation Speaker"
        case .shrine:
            return "Quiet Shrine"
        case .chest:
            return "Weathered Chest"
        case .bed:
            return "Traveler's Cot"
        case .gate:
            return "Rust Gate"
        case .beacon:
            return "Dormant Beacon"
        case .plate:
            return "Stone Plate"
        case .switchRune:
            return "Rune Switch"
        }
    }

    var defaultLines: [String] {
        switch self {
        case .npc:
            return ["A silent marker waits for a proper NPC record."]
        case .shrine:
            return ["The shrine is cold, but ready to take a new ritual."]
        case .chest:
            return ["The lid groans when it opens."]
        case .bed:
            return ["A rough bed offers a safe place to rest."]
        case .gate:
            return ["The gate's latch is not yet assigned."]
        case .beacon:
            return ["A beacon core could be mounted here one day."]
        case .plate:
            return ["The stone sinks slightly beneath your weight."]
        case .switchRune:
            return ["A rune flickers, waiting for a sequence."]
        }
    }
}
