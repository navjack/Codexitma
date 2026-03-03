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

## Current Notes

- Graphics mode should be the main path for day-to-day iteration.
- Terminal mode is still useful for quick smoke tests and headless validation.
- The engine is still shared between both renderers, so gameplay changes should continue to land in the core model/engine first.
- After each successful build, copy the runnable binary to the project root as `./Codexitma`.
- The current world path now includes explicit environmental puzzle steps instead of only location-based progression.

## Next Build Targets

- Expand the graphical combat feedback so hits, damage, and danger states are more legible.
- Continue expanding the world/content so the current slice grows toward the full multi-phase plan.
- Commit stable checkpoints frequently now that git is part of the workflow.
- Add more authored map events, optional treasure loops, and denser region-specific enemy encounters.
