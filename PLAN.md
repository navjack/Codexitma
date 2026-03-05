# Plan (Archived): `Ashes of Merrow` - Swift Terminal RPG for macOS

## Status

This file is the original greenfield project plan that kicked off `Codexitma`.

It is no longer an exact description of the shipped codebase. The project moved well beyond this terminal-first proposal into a graphics-first RPG engine with:

- a native macOS frontend
- an SDL3 cross-platform frontend and Win64 release build
- built-in audio, screenshot automation, and a headless bridge
- a first-class adventure editor
- external JSON adventure packs and overrides
- multiple adventures, visual themes, and a `Depth 3D` renderer

The historical design intent here is still useful, but the implementation details below should be read as archival planning, not current architecture.

For the current project surface, see:

- `README.md`
- `SCRATCHPAD.md`

## Summary

Build a greenfield, single-player 2D top-down RPG adventure game in **Swift 6** as a **terminal-first macOS app** using **Swift Package Manager**. The game will present like a hybrid of **Apple II-era exploration** and **MS-DOS text-mode adventure games**: fixed-grid rendering, low-color palette, tile-based movement, menu-driven interactions, and strict retro-era constraints.

I am choosing:
- **Terminal UI over AppKit/SpriteKit**
- **ASCII / box-drawing presentation over bitmap graphics**
- **Single executable Swift package**
- **No external dependencies by default**

This keeps the implementation focused, portable across macOS terminals, and faithful to the retro constraint brief.

## Product Direction

### Core fantasy
The player explores a fallen valley, uncovers why the old beacon towers went dark, solves environmental puzzles, fights hostile creatures, and restores a final tower to end the blight.

### Tone and style
- Melancholic but adventurous
- Sparse, atmospheric writing
- Low-fi text presentation with strong readability
- Retro constraints treated as a feature, not a limitation

### Chosen gameplay shape
- Top-down overworld exploration on a tile grid
- Small handcrafted world split into connected zones
- Turn-based movement and combat
- Simple inventory and quest flags
- 4-6 hours of total playtime target
- Save/load support

## Scope

### In scope
- Playable terminal game loop
- World exploration
- NPC dialogue
- Turn-based encounters on the same map
- Items, keys, healing, one ranged tool
- Environmental puzzles
- Story progression with an ending
- Save/load to local JSON file

### Out of scope
- Procedural generation
- Multiplayer
- Modding
- Audio
- Networking
- Pixel art / native window rendering
- Real-time combat

## Technical Direction

### Platform and tooling
- Language: **Swift**
- Package manager: **Swift Package Manager**
- Target: macOS command-line executable
- Minimum target assumption: macOS 14+
- Entry point: `Sources/Game/main.swift`

### Rendering model
Use ANSI terminal control sequences for:
- Clear screen
- Cursor repositioning
- Color changes
- Hiding/showing cursor

Fallback behavior:
- If ANSI color is unsupported, run in monochrome mode
- If terminal size is too small, show a resize prompt and pause until valid

### Terminal constraints (locked)
- Visible playfield: **60x22**
- Status + log area: **20x22** side panel, yielding an **80x24** expected terminal
- Fixed update cadence: input-driven turns, not frame-driven animation
- Tile glyphs restricted to ASCII plus common box characters when available
- Palette limited to 8 base ANSI colors

## Game Design Spec

### World structure
Use 6 connected regions:
1. Village of Merrow (safe hub)
2. South Fields (intro/tutorial area)
3. Sunken Orchard (first puzzle zone)
4. Hollow Barrows (combat-heavy dungeon)
5. Black Fen (navigation hazard area)
6. Beacon Spire (final dungeon / ending)

Each region is a hand-authored tilemap loaded from local data files.

### Main progression
1. Wake in Merrow after the beacon fails
2. Receive first objective from village elder
3. Restore power to two outer relay shrines
4. Gain access to the Black Fen route
5. Recover the Lens Core from the Barrows
6. Reach Beacon Spire and reactivate the beacon
7. Final encounter and ending scene

### Core systems
- Movement: 4-directional, one tile per turn
- Collision: walls, water, locked gates, interactables
- Interaction: `Space` or `E`
- Inventory: small fixed-capacity list
- Combat: bump-to-engage, still resolved in-map turn mode
- Dialogue: typewriter-style text reveal can be skipped
- Quests: hidden flag-based progression, optional journal page
- Save points: manual save at beacons and beds; optional quick-save on quit

### Player stats
- Health
- Stamina
- Attack
- Defense
- Lantern charge (used in dark areas / ranged tool gating)

### Items
- Healing tonic
- Iron key / shrine keys
- Lantern oil
- Charm fragments (optional upgrades)
- Lens Core (main quest artifact)

### Enemies
- Crows
- Root Hounds
- Mire Wraiths
- Barrow Sentinels
- Final boss: The Shaded Keeper

### Puzzle types
- Pressure plates
- Switch ordering
- Light-routing with beacon mirrors
- Key-and-gate traversal
- One “darkness” visibility restriction in Black Fen

## Architecture

### Package layout
- `Sources/Game/main.swift`
- `Sources/Game/App/GameApp.swift`
- `Sources/Game/Engine/`
- `Sources/Game/Model/`
- `Sources/Game/Systems/`
- `Sources/Game/Rendering/`
- `Sources/Game/Input/`
- `Sources/Game/Content/`
- `Sources/Game/Persistence/`
- `Tests/GameTests/`

### Major modules
- **App**: process startup, terminal setup/teardown, main loop
- **Engine**: state machine, scene transitions, turn resolution
- **Rendering**: terminal buffer, ANSI output, HUD/log drawing
- **Input**: key parsing and command mapping
- **Model**: core data types
- **Systems**: combat, interactions, AI, quests
- **Content**: maps, dialogue, item definitions, NPCs
- **Persistence**: save/load serialization

## Public Interfaces and Types

These are the core interfaces the implementation should expose internally and stabilize early.

### Core enums
- `enum GameMode { case title, exploration, dialogue, inventory, combat, pause, gameOver, ending }`
- `enum TileType { case floor, wall, water, brush, doorLocked, doorOpen, shrine, stairs, beacon }`
- `enum Direction { case up, down, left, right }`
- `enum ActionCommand { case move(Direction), interact, openInventory, confirm, cancel, help, quit }`

### Core structs
- `struct Position { var x: Int; var y: Int }`
- `struct Tile { var type: TileType; var glyph: Character; var walkable: Bool; var color: ANSIColor }`
- `struct Item { let id: ItemID; let name: String; let kind: ItemKind; let value: Int }`
- `struct PlayerState { ...stats, inventory, position, currentMapID... }`
- `struct NPCState { let id: NPCID; var position: Position; var dialogueState: Int }`
- `struct EnemyState { let id: EnemyID; var position: Position; var hp: Int; var ai: AIKind }`
- `struct QuestState { var flags: Set<QuestFlag> }`
- `struct SaveGame: Codable { var player: PlayerState; var world: WorldState; var quests: QuestState; var playTimeSeconds: Int }`

### Core protocols
- `protocol Scene { func render(into: inout ScreenBuffer, state: GameState); mutating func handle(_ command: ActionCommand, engine: inout GameEngine) }`
- `protocol RenderableEntity { var position: Position { get }; var glyph: Character { get }; var color: ANSIColor { get } }`

### Core engine types
- `struct GameState`
- `final class GameEngine`
- `struct ScreenBuffer`
- `final class TerminalRenderer`
- `final class InputReader`
- `final class SaveRepository`

### Data/content interfaces
- `struct MapDefinition: Decodable`
- `struct DialogueNode: Decodable`
- `struct EncounterDefinition: Decodable`

## Data Format Decisions

### Map storage
Store maps as local JSON or compact text assets. Chosen default:
- **ASCII map files** for layout
- **JSON sidecar** for metadata (spawns, exits, triggers)

Reason: easier to author, inspect, and patch.

### Save storage
- Path: `~/Library/Application Support/AshesOfMerrow/savegame.json`
- Single save slot in initial implementation
- Atomic write via temp file + replace

### Content loading
All game content loads at startup and is validated before the title screen. Fatal content errors should fail fast with a human-readable terminal message.

## Input Spec

### Key mapping
- `WASD` or arrow keys: movement
- `E` or `Space`: interact / confirm
- `I`: inventory
- `J`: journal/help
- `Esc` or `Q`: pause / back
- `S`: save when allowed
- `L`: load from title screen

### Input behavior
- Single-key input, no Enter required
- If raw terminal mode cannot be enabled, fallback to line-input mode with a warning and alternate command prompt

## Rendering Spec

### Screen composition
- Left: playfield
- Right: HUD
- Bottom lines (within side panel or reserved row): rolling event log

### HUD content
- Player name
- HP / max HP
- Stamina
- Lantern charge
- Current region
- Active objective
- Key item count

### Visual conventions
- Player: `@`
- Friendly NPC: `&`
- Hostile enemy: `g`, `h`, `w`, etc.
- Doors/gates: `+`
- Water: `~`
- Brush: `"`
- Shrine/goal: `*`

## Gameplay Rules

### Movement and turns
- Every player action consumes one turn
- Enemy AI updates after each valid player turn
- Invalid movement does not consume a turn but writes a short log message

### Combat
- Triggered when attacking or colliding into hostile target
- Damage formula is deterministic with a small random range
- Enemy telegraphs via log line before special actions
- Player can attack, use item, or retreat if adjacent path exists
- No separate battle screen; combat remains in-map

### Death and failure
- On defeat, return to last save point
- Lose 10% carried consumables rounded down, never quest items
- Log a clear recovery message to avoid frustration

### Difficulty
- Single default difficulty
- Tuned for low frustration and steady progress
- Optional hidden “Iron Lantern” mode is out of scope for v1

## Testing and Validation

### Automated tests
- Map parser validates rectangular bounds and legal glyphs
- Collision tests for all blocking tile types
- Combat formula tests for deterministic min/max output
- Save/load round-trip tests
- Quest flag transition tests
- Input parser tests for ANSI escape sequences and fallback keys
- Terminal buffer diff tests to ensure stable rendering writes

### Manual playtest scenarios
1. New game starts, title renders correctly in 80x24 terminal
2. Player can move, collide, interact, and open inventory
3. First shrine can be activated only after obtaining its required item
4. Enemy turn order behaves consistently
5. Death returns player to last valid save point
6. Save persists across app restart
7. Final quest chain can be completed end-to-end without soft lock
8. Game remains usable in monochrome fallback mode

### Acceptance criteria
- Full playable beginning-to-end path with no blockers
- No crashes during normal play path
- Terminal restored correctly on exit, including interrupt/quit paths
- Save file corruption is handled gracefully with a recovery message
- All six regions load and connect correctly

## Implementation Phases

These phase notes are historical. In practice, the project has already moved through and past them, with major scope additions not captured in this original plan.

### Phase 1: Foundation
- Initialize Swift package executable
- Implement terminal raw mode handling and cleanup
- Build ANSI renderer and double-buffered `ScreenBuffer`
- Add title screen and resize gate

### Phase 2: Engine skeleton
- Add `GameState`, `GameMode`, and main loop
- Add input reader and command mapping
- Add scene switching and event log

### Phase 3: Exploration
- Implement map loading
- Add tile collision, region transitions, interactables
- Render world, entities, and HUD

### Phase 4: Systems
- Add inventory, NPC dialogue, quest flags
- Add enemy AI and in-map combat
- Add item use and stat effects

### Phase 5: Content
- Author six regions
- Add story text, NPCs, enemies, puzzles
- Tune progression to avoid soft locks

### Phase 6: Persistence and polish
- Add save/load
- Add fallback modes and terminal capability checks
- Add test coverage and balancing passes

## Risks and Mitigations

- **Terminal portability issues**: keep ANSI usage conservative and provide monochrome fallback
- **Raw input edge cases**: isolate terminal mode setup/teardown and test abnormal exits
- **Content soft locks**: use explicit quest flags and validation checks for required items and triggers
- **Unreadable text UI**: enforce fixed layout and minimum terminal size

## Assumptions and Defaults

- The repo is currently empty; this is a new project.
- No external libraries will be used unless raw terminal input proves impractical.
- The game will target modern macOS terminals, primarily Terminal.app and iTerm2.
- The chosen default presentation is **terminal retro text mode**, not a native graphical app.
- The chosen aesthetic is a **DOS/Apple II-inspired hybrid**, but implemented with modern Swift and ANSI terminal control.
- Single save slot is sufficient for v1.
- All story, naming, and art direction are fully delegated, so this plan locks them without further approval.
