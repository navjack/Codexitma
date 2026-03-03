# Codexitma

`Codexitma` is a Swift 6 macOS RPG in the spirit of early Ultima and Apple II fantasy games, now with a Gemstone Warrior-inspired graphics mode: tile-based exploration, turn-driven movement and combat, fixed-color low-resolution presentation, and a compact but expanding handcrafted world.

## Current State

The project has working implementations of all six planned phases at a foundational level:

- Foundation: package, launcher, save system, content loading
- Engine: state machine, movement, interaction, combat, quests
- Exploration: six connected regions with map transitions
- Systems: dialogue, inventory, enemies, puzzle gates
- Content: a complete start-to-finish playable adventure slice
- Persistence and polish: save/load, graphics mode, terminal mode, headless automation

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

## Automation

There is a built-in headless control surface for deterministic testing and scripted play:

- `--script "new,e,state"`
- `--script-file path/to/commands.txt --step-json`
- `--bridge`

See [AUTOMATION.md](/Volumes/4terrybi/coding/Codexitma/AUTOMATION.md) for details.

This is the preferred near-term way to automate playthroughs. If an MCP server is added later, it should wrap the bridge instead of reimplementing game logic.

## Content Direction

The current adventure is `Ashes of Merrow`, but the codebase is being pushed toward a broader "Codexitma" engine style:

- more region-specific encounters
- more optional treasure and side discoveries
- Gemstone Warrior-style chamber rendering in graphics mode
- more readable low-resolution sprites and stronger room silhouettes
- eventually, richer content packaging once quest flow is less hardcoded

## Repo Notes

- `PLAN.md` holds the original project plan and design direction.
- `SCRATCHPAD.md` is the running in-repo development notebook.
- Git is now the default workflow; stable milestones are committed frequently.
