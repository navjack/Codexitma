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
  - a new launch path reserved for the upcoming SDL frontend

The `--sdl` flag is now parsed and routed through the app, but the SDL renderer is still a stub. The branch is not pretending the SDL frontend exists yet; it is reserving the runtime shape we will fill in next.

## Immediate Next Steps

1. Move more graphics runtime logic behind backend-neutral interfaces.
2. Extract a render-friendly scene snapshot from `GameState` so SDL does not depend on SwiftUI views.
3. Add an SDL window, software framebuffer, input translation, and a present loop.
4. Bring over the existing visual themes in stages:
   - Ultima first
   - Gemstone second
   - Depth 3D last
5. Revisit sound after rendering/input are stable.

## Constraints

- Keep this branch local-only until the SDL backend is genuinely usable.
- Do not regress the existing native macOS graphics frontend while extracting shared logic.
- Ignore the terminal frontend unless it helps with testing or core-engine verification.
