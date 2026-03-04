# SDL Port Notes

This branch is the start of the cross-platform graphics port for `Codexitma`.

## Goal

Replace the current AppKit-only graphics frontend with a second frontend built on SDL so the graphical version can eventually run on:

- Linux
- Windows
- macOS

The terminal frontend is not the target here except where it remains useful for testing.

## Current Branch Status

This branch now has a real graphics backend seam:

- `native`
  - the existing AppKit + SwiftUI frontend
- `sdl`
  - a live SDL3 frontend on this branch

The `--sdl` flag is now a working launch path:

- it opens a real SDL3 window
- it drives the shared `GameEngine`
- it renders a low-resolution top-down board view
- it renders a minimal `Depth 3D` raycast view when that visual theme is active
- it uses the same backend-neutral `GraphicsSceneSnapshot` data that now also feeds the native map renderer

This is still an early renderer, not feature parity. It is enough to prove the cross-platform direction and to keep iterating on a real SDL path instead of a stub.

## Immediate Next Steps

1. Move more graphics runtime logic behind backend-neutral interfaces so SDL no longer depends on the remaining AppKit-only presentation helpers.
2. Replace the current SDL debug-text HUD with a proper low-res bitmap text pass so the SDL frontend has a fully controlled visual style.
3. Make the SDL frontend responsive to live window size instead of using the current fixed-layout frame math.
4. Add proper sprite-pattern rendering for SDL billboards instead of the current solid-color rectangle approximation.
5. Revisit sound after rendering/input are stable, ideally via an SDL-backed audio path instead of AVFoundation.

## Constraints

- Keep this branch local-only until the SDL backend is genuinely usable.
- Do not regress the existing native macOS graphics frontend while extracting shared logic.
- Ignore the terminal frontend unless it helps with testing or core-engine verification.
