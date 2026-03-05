# SDL Frontend Notes

These notes track the current SDL frontend after its merge into `main`.

They are not branch-start notes anymore. The SDL path is already part of the shipping project.

## Current Role

- macOS native graphics remains the primary local frontend.
- SDL3 is the cross-platform graphics path.
- Win64 release artifacts ship from the SDL frontend.
- macOS can also run SDL with `--sdl` for parity testing.
- Linux is still an intended SDL target, but packaged Linux artifacts are not published yet.

## What SDL Already Covers

The SDL frontend now shares the same game/session backend as native graphics and is no longer limited to exploration-only rendering.

Current working coverage includes:

- title screen and adventure selection
- character creation
- exploration and combat
- dialogue, inventory, shops, and ending flow
- `Gemstone`, `Ultima`, and `Depth 3D` themes
- authored `Depth 3D` backdrops (`sky` and `ceiling`)
- shared world-space depth lighting and shadowing
- in-window screenshot capture
- lighting debug overlay (`F10`)
- in-window editor entry from title or active gameplay
- SDL-native editor shell for both map and non-spatial content editing
- graphics script automation for reproducible screenshots and UI checks

## Platform Notes

### macOS

- Native graphics is still the default and preferred path.
- SDL is mainly a parity harness and cross-platform validation path.

### Windows

- Windows builds use SDL as the real graphics frontend.
- GitHub Actions produces the Win64 artifact from the SDL path.
- The Windows build uses portable local data folders next to the executable when possible.

### Linux

- Shared runtime and SDL-facing code are being kept compatible with the Linux target path.
- Packaging and release publishing are still pending.

## Remaining Gaps

SDL is functionally close to the native frontend, but a few areas still deserve routine parity work:

- more editor polish and richer text-entry workflows
- additional small-window layout compression
- continued visual tuning between native and SDL themes
- future Linux packaging and distribution work

## Working Rules

- Do not regress the native macOS frontend while changing shared graphics/session code.
- Treat SDL and native as functionally aligned frontends, even when their visual presentation differs.
- Prefer fixing gameplay/editor feature gaps in shared runtime code first, then wiring the UI per frontend.
