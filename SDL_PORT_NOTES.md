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

This is still an early renderer, not feature parity. It is enough to prove the cross-platform direction and to keep iterating on a real SDL path instead of a stub.

## Immediate Next Steps

1. Keep closing feature gaps between the native and SDL frontends until SDL reaches gameplay/UI parity on macOS.
2. Replace the current SDL debug-text HUD with a proper low-res bitmap text pass so the SDL frontend has a fully controlled visual style.
3. Make the SDL frontend responsive to live window size instead of using the current fixed-layout frame math.
4. Add proper sprite-pattern rendering for SDL billboards instead of the current solid-color rectangle approximation.
5. Once parity is acceptable, start splitting platform selection so macOS prefers native while Windows/Linux use SDL as the real graphics path.

## Constraints

- Keep this branch local-only until the SDL backend is genuinely usable.
- Do not regress the existing native macOS graphics frontend while extracting shared logic.
- Ignore the terminal frontend unless it helps with testing or core-engine verification.
