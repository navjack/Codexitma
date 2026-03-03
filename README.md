# Codexitma

`Codexitma` is a Swift 6 macOS RPG in the spirit of early Ultima and Apple II fantasy games, with selectable low-res graphics themes, simple Apple II-style square-wave audio in graphics mode, and multiple adventures running on the same engine.

## Current State

The project has working implementations of all six planned phases at a foundational level:

- Foundation: package, launcher, save system, content loading
- Engine: state machine, movement, interaction, combat, quests
- Exploration: multi-region worlds with map transitions, side interiors, and optional areas
- Systems: dialogue, inventory, enemies, puzzle gates
- Content: two playable adventures with different identities and map graphs
- Persistence and polish: save/load, graphics mode, terminal mode, headless automation, persistent graphics theme selection

What is still expanding is depth, not the existence of those phases. The engine is real; the adventure is still growing.

## Run

Build and run the default low-resolution graphics mode:

```sh
swift run Game
```

Run the retro ANSI terminal mode instead:

```sh
swift run Game --terminal
```

After successful local builds, a runnable copy is also kept at the project root:

```sh
./Codexitma
```

## Controls

- `WASD` or arrow keys: move
- `E` or `Space`: interact / talk / use nearby object
- `I`: open the pack / inventory
- `J` or `H`: show current objective
- `K`: save
- `L`: load
- `Q`: cancel / back
- `X`: quit
- `T` in graphics mode: cycle the visual theme (`Gemstone` / `Ultima`)

## Adventures

- `Ashes of Merrow`: the original beacon-restoration campaign through a dark valley.
- `Starfall Requiem`: a larger salvage-coast campaign with a hub town, store buildings, side dungeons, more optional treasure, and a fallen sky-engine finale.

Choose the adventure on the title screen with `A/D` or left/right before starting a new hero.

## Content Packs

Most authored game content now lives in bundled JSON data packs instead of Swift source:

- global tables: [adventure_catalog.json](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData/adventure_catalog.json), [items.json](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData/items.json), [hero_templates.json](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData/hero_templates.json)
- per-adventure packs: [ashes_of_merrow](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData/adventures/ashes_of_merrow), [starfall_requiem](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData/adventures/starfall_requiem)
- shared map graphs and layouts: [ContentData](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData)

That includes adventure metadata, class templates, items, objectives, dialogue, encounters, NPCs, enemies, and shop inventories. Core engine rules and quest-flag control flow still live in Swift.

## Automation

There is a built-in headless control surface for deterministic testing and scripted play:

- `--script "new,e,state"` for the default adventure
- `--script "right,new,e,state"` to start `Starfall Requiem`
- `--script-file path/to/commands.txt --step-json`
- `--bridge`

See [AUTOMATION.md](/Volumes/4terrybi/coding/Codexitma/AUTOMATION.md) for details.

This is the preferred near-term way to automate playthroughs. If an MCP server is added later, it should wrap the bridge instead of reimplementing game logic.

## Content Direction

The current adventure is `Ashes of Merrow`, but the codebase is being pushed toward a broader "Codexitma" engine style:

- more region-specific encounters
- more optional treasure and side discoveries
- Gemstone Warrior-style chamber rendering in graphics mode
- switchable Gemstone / Ultima presentation themes in graphics mode
- persistent graphics theme preference between launches
- simple square-wave walking / attack / item / intro sounds in graphics mode
- more readable low-resolution sprites and stronger room silhouettes
- deeper data-driven progression once the next round of quest/state systems is expanded

## Repo Notes

- `PLAN.md` holds the original project plan and design direction.
- `SCRATCHPAD.md` is the running in-repo development notebook.
- Git is now the default workflow; stable milestones are committed frequently.
