# Codexitma

Codexitma is a Swift 6 retro RPG engine for macOS with a playable low-resolution fantasy game, a built-in adventure editor, and a data-driven content pipeline.

It is deliberately styled after early Apple II and Ultima-era computer RPGs, with a modern codebase underneath: native graphics mode, terminal mode, JSON content packs, deterministic automation hooks, and an in-game editor workflow.

## What It Is

- Graphics-first macOS RPG with low-resolution retro presentation
- Native AppKit/SwiftUI windowed mode plus ANSI terminal mode
- Three graphics styles on the same game state:
  - `Gemstone`
  - `Ultima`
  - `Depth 3D`
- Simple Apple II-style square-wave sounds in graphics mode
- Two playable adventures on the same engine
- Character creation with classes, traits, skills, starting gear, and inventory
- Built-in graphical adventure editor
- External JSON adventure packs and override mods
- Headless automation bridge for scripted runs and regression testing

## Current State

The project is beyond prototype status. The engine, save/load flow, combat, quests, exploration, shops, class-based hero starts, graphics themes, editor, and external content loading are all working.

What is still evolving is depth and content scale:

- more authored encounters
- longer campaigns
- more systems depth
- more editor polish
- more visual refinement

The core engine and tooling are already real and usable.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain (the package is set to Swift tools `6.3`)

## Quick Start

Build and run the default graphics mode:

```sh
swift run Game
```

Run the ANSI terminal mode:

```sh
swift run Game --terminal
```

Launch directly into the graphical editor:

```sh
swift run Game --editor
```

After successful builds, a convenience copy of the latest working binary is also kept at the repo root:

```sh
./Codexitma
```

## Gameplay Features

- Tile-based top-down exploration
- Turn-based movement and combat
- Dialogue and NPC interaction
- Inventory, consumables, gear, and equippable slots
- Shops and `marks` currency
- Environmental puzzle gates
- Adventure selection from the title screen
- Save/load support
- Persistent graphics theme preference between launches

## Graphics Modes

`Codexitma` supports three visual themes in graphics mode. They all run on the same underlying engine state.

- `Gemstone`
  - high-contrast chamber look inspired by early action-RPG screens
- `Ultima`
  - flatter overworld-style board with stricter classic field readability
- `Depth 3D`
  - first-person raycast dungeon view with turn-in-place controls and map-accurate depth

In graphics mode, press `T` to cycle styles.

## Controls

### General

- `WASD` or arrow keys: move
- `E` or `Space`: interact / confirm
- `I`: open inventory / leave inventory / leave shop
- `J` or `H`: show objective / inspect selected entry
- `K`: save
- `L`: load
- `Q`: cancel / back
- `X`: quit
- `T`: cycle graphics theme
- `M`: open the editor (graphics mode)

### Depth 3D

When `Depth 3D` is active during exploration:

- `W` / Up: move forward
- `S` / Down: step backward
- `A`: turn left
- `D`: turn right

### Shops

- movement keys: change selected offer
- `E`: buy selected offer
- `J`: inspect selected offer
- `Q` or `I`: leave the counter

## Included Adventures

- `Ashes of Merrow`
  - the original dark-valley beacon restoration campaign
- `Starfall Requiem`
  - a larger salvage-coast adventure with a hub town, stores, dungeons, and a late-game sky-engine path

Choose the active adventure on the title screen before starting a new character.

## Built-In Editor

The graphical editor is a first-class part of the app, not just a dev-only tool.

You can open it in three ways:

- `swift run Game --editor`
- `M` from the title screen
- `M` during a live adventure, followed by confirmation

Current editor capabilities:

- create a blank template adventure
- load bundled adventures for safe override editing
- reopen and edit external user packs
- paint terrain on maps
- place NPCs, enemies, interactables, portals, and spawn points
- edit dialogue, quest flow, encounters, shops, NPCs, and enemies
- validate content before export
- export and immediately playtest the active pack

Bundled adventures are never edited in-place. Editing a bundled adventure writes an external override pack instead.

See [EDITOR_ROADMAP.md](EDITOR_ROADMAP.md) for the editor-specific notes and remaining polish targets.

## Content Packs And Mods

Most authored content is now externalized into JSON rather than hardcoded in Swift.

Bundled data lives under:

- `Sources/Game/ContentData`
- `Sources/Game/ContentData/adventures/ashes_of_merrow`
- `Sources/Game/ContentData/adventures/starfall_requiem`

This includes:

- adventure metadata
- hero templates
- item definitions
- objective flow
- dialogue
- encounters
- NPCs
- enemies
- shops
- map layouts

External adventure packs are loaded from:

```text
~/Library/Application Support/Codexitma/Adventures
```

Each pack lives in its own folder and provides the same JSON-driven content structure.

If an external pack uses the same adventure `id` as a bundled adventure, it overrides the bundled one. That is the supported mod path for changing shipped adventures without touching the app bundle.

## Automation And Testing

Codexitma includes a built-in headless control surface for scripted play and regression testing.

Examples:

```sh
swift run Game --script "new,e,state"
swift run Game --script "right,new,e,state"
swift run Game --script-file path/to/commands.txt --step-json
swift run Game --bridge
```

The bridge is the preferred automation surface. If an MCP server is added later, it should wrap this interface instead of duplicating game logic.

See [AUTOMATION.md](AUTOMATION.md) for details.

## Repository Notes

- [PLAN.md](PLAN.md) contains the original project plan and scope.
- [SCRATCHPAD.md](SCRATCHPAD.md) is the running development notebook.
- `main` is the canonical development branch.

## Development

Run the test suite:

```sh
swift test
```

The project is organized as a Swift Package with:

- executable target: `Game`
- test target: `GameTests`

## Road Ahead

The current priorities are straightforward:

- expand adventure content
- deepen systems for replayability
- keep refining the editor
- continue improving the retro visual presentation without breaking the low-resolution design goal
