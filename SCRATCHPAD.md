# Scratchpad

## Project Reference

- `PLAN.md` is the project source of truth for scope, systems, and narrative direction.
- The current implementation now supports a native macOS graphics-first renderer, with `--terminal` retained as a fallback for the original ANSI mode.

## Development Log

### 2026-03-03

- Added a running scratchpad so progress notes live in-repo instead of only in chat.
- Switched the default launch path from terminal rendering to a native macOS graphical window.
- Kept the terminal gameplay loop intact behind `--terminal` so the original retro mode still works.
- Added a SwiftUI/AppKit windowed interface with tile-like shapes, HUD panels, on-screen controls, and arrow-key movement support.
- Tightened the graphics direction toward an Apple II / early Ultima look with a fixed palette, hard-edged panels, enlarged low-res tiles, and block sprites.
- Standardized the graphical identity around the `Codexitma` name.
- Generalized NPCs so multiple named characters can exist across regions without hardcoded one-off map logic.
- Added actual puzzle gating: paired pressure plates in the Black Fen and an ordered mirror-switch sequence in the Beacon Spire.
- Added a headless automation layer: `--script` for deterministic command runs and `--bridge` for stdin-driven JSON snapshots.
- Surfaced clearer on-screen control legends so the UI states what each key actually does.
- Reworked the native graphics renderer toward a Gemstone Warrior (1984) influence: bright chamber borders, black void framing, patterned room floors, and chunkier low-res sprites.
- Fixed the graphics key handler so `Q` now actually behaves as back/cancel instead of quitting.
- Repacked the graphics HUD into a shorter two-column dashboard so the full game view fits comfortably inside the default window and stays within a 1080p-class presentation target.
- Added selectable graphics presentation themes in the native UI: `Gemstone` for chamber-heavy contrast and `Ultima` for a flatter overworld-style board, both driven by the same engine state.
- Added a second full adventure, `Starfall Requiem`, with a larger map graph, interior buildings, side dungeons, more NPCs, and broader encounter density.
- Persisted the graphics visual theme between launches and added simple Apple II-style square-wave cues for intro, movement, attacks, and item use in graphics mode.
- Moved authored content out of hardcoded Swift tables and into bundled JSON data packs: adventure catalog, class templates, items, objectives, dialogue, encounters, NPCs, enemies, and shop definitions.
- Added live merchant support: externalized shop definitions now open real in-game stores, spend `marks`, persist sold-out stock, and surface through both renderers plus the automation bridge.
- Replaced hardcoded quest objective sequencing with JSON quest-flow stages so progression order now lives in data packs.
- Added support for third-party adventure packs loaded from `~/Library/Application Support/Codexitma/Adventures`, with dynamic title-screen discovery.
- Fixed the inventory UI so packs scroll past five items, clearly highlight the active selection, and allow dropping non-essential items with `R`.
- Started the `codex/3d-renderer` branch and added a first-person pseudo-3D graphics theme that reads the same map data as the 2D renderers.
- Added real dungeon-crawler controls for `Depth 3D`: turn in place left/right and move forward/back without forcing the camera to rotate.
- Replaced the old hallway-only `Depth 3D` presentation with a tile-accurate raycast view, including draw distance plus floor and sky/ceiling depth cues for better spatial reading.
- Added wall-occluded billboard projection for visible enemies, NPCs, and interactables in `Depth 3D`, and introduced a dedicated `--editor` graphical adventure editor that exports full external packs or override mods.
- Started `codex/editor-suite` to focus the editor buildout and documented the current editor scope, data model, gaps, and implementation milestones in `EDITOR_ROADMAP.md`.
- Completed the first editor interaction pass: added explicit editor tools (`Terrain`, `NPC`, `Enemy`, `Interactable`, `Portal`, `Spawn`, `Erase`, `Select`), layered object placement on the map canvas, selection summaries, and map-id rename cascading for layered references.
- Began the first real inspector pass in the editor: selected NPCs, enemies, interactables, and portals can now be edited from the right-side panel instead of only being summarized.
- Completed the editor-suite milestone push: added content tabs for dialogues, quest flow, encounters, shops, NPCs, and enemies; seeded blank packs with playable starter data; and added `SAVE + PLAYTEST` so the editor can export and launch directly into the current adventure.
- Filled in more inspector coverage so enemies expose AI, interactables expose reward/flag fields, and portals expose destination coordinates.
- Finished the merge-blocking editor polish pass: added pre-export validation with surfaced issues, interactable `rewardMarks`, portal gate text/flag authoring, and promoted the editor into a first-class graphics-mode feature via `M` from the title screen or a live run with a confirmation prompt.
- Bundled adventures now open in the editor as safe external overrides, while external packs and existing user mods reopen and save back into their existing pack folder.

## Current Notes

- Graphics mode should be the main path for day-to-day iteration.
- Terminal mode is still useful for quick smoke tests and headless validation.
- The engine is still shared between both renderers, so gameplay changes should continue to land in the core model/engine first.
- After each successful build, copy the runnable binary to the project root as `./Codexitma`.
- The current world path now includes explicit environmental puzzle steps instead of only location-based progression.
- The new bridge is a better immediate fit than a full MCP server, and can be wrapped by MCP later if needed.
- The graphics mode is now the strongest presentation path: Gemstone-like chamber screens on top of the existing Apple II / Ultima mechanical base.
- Keep the graphics layout bounded for at least a 1080p window; if more UI is added later, prefer widening panels or adding compact rows before making the window taller.
- Theme selection is now a UI concern only; keep future visual experiments in the renderer/session layer rather than pushing them into `GameEngine`.
- Content authoring should now default to the JSON packs in `Sources/Game/ContentData`; only core rules, state transitions, and rendering logic should require Swift changes.
- External content packs can now extend the title menu without modifying the app bundle, as long as they follow the expected manifest and JSON file layout.

## Next Build Targets

- Expand the graphical combat feedback so hits, damage, and danger states are more legible.
- Continue expanding the world/content so the current slice grows toward the full multi-phase plan.
- Commit stable checkpoints frequently now that git is part of the workflow.
- Add more authored map events, optional treasure loops, and denser region-specific enemy encounters.
- Build a full scripted playthrough using the bridge so progression can be regression-tested end to end.
- Expand the external pack format so third-party adventures can define custom quest flags and bespoke item tables, not just reuse the built-in systems.
