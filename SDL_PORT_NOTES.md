# SDL Port Notes

This branch is the start of the cross-platform graphics port for `Codexitma`.

## Goal

Replace the current AppKit-only graphics frontend with a second frontend built on SDL so the graphical version can eventually run on:

- Linux
- Windows
- macOS

The terminal frontend is not the target here except where it remains useful for testing.

The intended end state is:

- macOS ships with the native AppKit + SwiftUI frontend as the default and primary experience.
- SDL exists to reach Windows and Linux.
- SDL may remain available on macOS as a parity/test harness, but not as the preferred macOS shipping frontend.

## Current Branch Status

This branch now has a real graphics backend seam:

- `native`
  - the existing AppKit + SwiftUI frontend
- `sdl`
  - a live SDL3 frontend on this branch

The `--sdl` flag is now a working launch path:

- it opens a real SDL3 window
- it drives the shared `SharedGameSession`, which now also powers the native frontend
- it renders a low-resolution top-down board view
- it renders a minimal `Depth 3D` raycast view when that visual theme is active
- it uses the same backend-neutral `GraphicsSceneSnapshot` data that now also feeds the native map renderer
- it now has mode-aware coverage for title, character creation, dialogue, inventory, shop, and ending states instead of only exploration
- it now uses a real built-in low-resolution bitmap text pass instead of SDL debug text
- it now renders patterned top-down sprites and patterned depth billboards instead of only flat solid rectangles
- it now lays itself out from the live SDL render size instead of assuming the initial window size forever
- it now opens a first SDL-native in-window editor shell from the same `M` confirmation flow, so map editing, tool application, validation, and pack saves no longer depend on AppKit
- the SDL editor now uses its own distinct cyan/blue editor chrome instead of looking nearly identical to the live game screen, and `X` now returns to gameplay instead of quitting the whole app
- the editor now has a backend-neutral `AdventureEditorSession` seam and renderer-neutral canvas overlay data, so the eventual SDL-native editor path no longer depends on SwiftUI colors inside editor state
- the SDL editor now reaches into the non-spatial content tabs too: dialogue, quest, encounter, shop, NPC, and enemy tabs all have cycle-based in-window editing controls instead of being map-only dead ends

This is still an early renderer, not full feature parity. The SDL editor shell now covers both spatial and non-spatial workflows, but it is still a cycle-based editor and not yet a full text-entry replacement for the richer native SwiftUI editor.

## Immediate Next Steps

1. Keep closing feature gaps between the native and SDL frontends until SDL reaches gameplay/UI parity on macOS.
2. Add richer SDL layout logic for very small windows so the mode-specific screens can compress more gracefully when vertical space is tight.
3. Push tile-surface fidelity higher in SDL so board cells better match the native Gemstone/Ultima visual language, not just the current low-res approximation.
4. Replace the remaining hardcoded SDL spacing constants with scale-aware metrics driven by the live viewport.
5. Add a real Windows Swift SDK bundle once a compatible one is available; `mingw-w64` and `zig` are now installed, but the local Swift toolchain still reports that no Swift SDKs are installed.
6. Once parity is acceptable, start splitting platform selection so macOS prefers native while Windows/Linux use SDL as the real graphics path.

## Constraints

- Keep this branch local-only until the SDL backend is genuinely usable.
- Do not regress the existing native macOS graphics frontend while extracting shared logic.
- Ignore the terminal frontend unless it helps with testing or core-engine verification.
