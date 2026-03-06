# Project Metrics

This file is a living snapshot of `Codexitma` size, structure, and content metrics.

It is meant to answer practical questions such as:

- how large the codebase is
- where the complexity currently sits
- how much test coverage exists in terms of declared tests
- how much authored game content ships with the repo
- which files are becoming the next refactor pressure points

## Snapshot

- Snapshot date: `March 5, 2026`
- Base commit: `f5e5611`
- Measurement tools:
  - `cloc 2.08`
  - `git`
  - `scripts/update_project_metrics.py`

## Headline Numbers

- Git commits: `90`
- Git-tracked files: `142`
- `cloc`-counted files: `123`
- Repository size on disk: `1.6G`

## Code Size

- Total `cloc` code lines: `22,469`
- Total `cloc` blank lines: `2,400`
- Total `cloc` comment lines: `101`

### By Language

- Swift: `68` files, `18,209` code lines
- JSON: `20` files, `2,244` lines
- Markdown: `9` files, `1,427` lines
- Shell: `3` files, `157` lines
- YAML: `2` files, `137` lines

### Raw Swift Line Counts

These are plain line counts rather than `cloc` code-line counts.

- Total Swift raw lines: `20,031`
- Production Swift under `Sources/`: `64` files, `18,789` lines
- Test Swift under `Tests/`: `3` files, `1,198` lines

### Swift Breakdown By Area

- App/frontend/editor layer: `48` files, `15,961` raw lines
- Engine layer: `6` files, `1,067` raw lines
- Model layer: `3` files, `1,253` raw lines
- Content loader layer: `3` files, `365` raw lines

## Testing

- Declared tests: `49`

## Bundled Game Content

- Embedded adventures: `2`
- Total bundled maps: `16`
- Total interactables: `62`
- Total portals: `28`
- Total dialogue entries: `16`
- Total encounter definitions: `4`
- Total NPC definitions: `14`
- Total enemy definitions: `25`
- Total shop definitions: `3`
- Total objective definition files: `4`
- Stable README screenshots in repo: `16`

### Adventure Breakdown

- `Ashes of Merrow`
  - maps: `6`
  - interactables: `24`
  - portals: `10`
  - dialogues: `6`
  - encounters: `2`
  - NPCs: `5`
  - enemies: `9`
  - shops: `0`
  - objective files: `2`

- `Starfall Requiem`
  - maps: `10`
  - interactables: `38`
  - portals: `18`
  - dialogues: `10`
  - encounters: `2`
  - NPCs: `9`
  - enemies: `16`
  - shops: `3`
  - objective files: `2`

## Largest Swift Files

1. [Sources/Game/App/SDLGraphicsLauncher+DepthRendering.swift](/Volumes/4terrybi/coding/Codexitma/Sources/Game/App/SDLGraphicsLauncher+DepthRendering.swift): `1137` lines
2. [Sources/Game/App/MapBoardView+DepthRendering.swift](/Volumes/4terrybi/coding/Codexitma/Sources/Game/App/MapBoardView+DepthRendering.swift): `939` lines
3. [Sources/Game/App/MapBoardView+DepthSupport.swift](/Volumes/4terrybi/coding/Codexitma/Sources/Game/App/MapBoardView+DepthSupport.swift): `782` lines
4. [Sources/Game/App/SDLGraphicsLauncher+SceneRendering.swift](/Volumes/4terrybi/coding/Codexitma/Sources/Game/App/SDLGraphicsLauncher+SceneRendering.swift): `737` lines
5. [Sources/Game/App/AdventureEditorSession.swift](/Volumes/4terrybi/coding/Codexitma/Sources/Game/App/AdventureEditorSession.swift): `693` lines

## What These Numbers Suggest

- The project is graphics-heavy. The majority of the codebase sits in rendering, frontend composition, editor UX, automation, and cross-platform presentation support.
- The engine core is comparatively compact. The complexity cost is mostly in presentation and tooling, not the turn-resolution rules themselves.
- `Depth 3D`, SDL parity, and the editor remain the biggest context-pressure zones.

## How To Refresh This File

Run:

```sh
./scripts/update_project_metrics.py
```

The script re-runs `cloc`, `git`, and the repo-specific aggregation logic, then rewrites this file in place.

Note: because `cloc` is run with `--vcs=git`, the snapshot measures the tracked repository state visible to `git` at generation time.
