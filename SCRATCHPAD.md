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
- Fixed the in-game editor window close path so closing the editor after launching it from a live adventure no longer releases the controller during AppKit's close callback.
- Made the editor and graphics UI layouts responsive: both now keep their wide-screen layouts when there is room, but fall back to stacked/scrollable arrangements inside smaller normal windows instead of overflowing.
- Started `codex/refactor-modules` and split the largest monolithic source files into smaller, logical Swift files: model types, graphics runtime, map renderer support, editor runtime/store/content/style, and the test suite now live in separate modules instead of a few giant files.
- Completed the second `codex/refactor-modules` pass: `GameEngine` is now split by behavior domain, `AdventureEditorStore` is split into document/canvas/content/helper extensions, and the editor chrome panels were extracted into dedicated SwiftUI subviews to reduce root-view context size.
- Fixed the in-game editor launch overlay so it renders as a true overlay instead of expanding the game window, and made the spawned editor window explicitly order to the front when opened from a live session.
- Fixed the editor window close path again: the controller now keeps the editor window alive through `windowWillClose` and only releases its strong references on the next main-queue turn, avoiding a crash when the user closes the editor window mid-session.
- Started the local-only `codex/sdl-cross-platform` branch and added an explicit graphics backend seam so `Codexitma` can launch either the native AppKit frontend or a new SDL frontend.
- Switched the branch target to SDL3.4.2 instead of SDL2 because SDL3 is installed locally and is the better long-term base for the cross-platform graphical port.
- Added a backend-neutral `GraphicsSceneSnapshot` layer so the active map board and depth-ray data can be built once from `GameState` and then consumed by multiple graphical frontends.
- Refactored the native `MapBoardView` to consume the shared scene snapshot for its active board/depth rendering path instead of pulling those visible cells directly from `GameState`.
- Replaced the SDL stub with a real SDL3 window, input loop, and low-resolution renderer: `--sdl` now launches, drives the shared `GameEngine`, renders a top-down board, and shows a minimal depth view when `Depth 3D` is active.
- Extracted a shared `SharedGameSession` runtime so the native AppKit frontend and the SDL frontend now use the same command handling, theme persistence, sound cue rules, and depth-control remapping.
- Expanded the scene snapshot to include mode-specific UI data (adventure selection, hero selection, dialogue, inventory, and shop state) so parity work does not require SDL to peek back into SwiftUI-only state.
- Upgraded the SDL frontend from an exploration-only viewer into a mode-aware frontend that now renders title, character creation, dialogue, inventory, shop, and ending states using the same shared session/snapshot pipeline.
- Replaced the SDL frontend's temporary debug-text pass with a built-in low-resolution bitmap font so the renderer has a controlled retro text style instead of relying on SDL debug helpers.
- Made the SDL renderer respond to the live render output size: board/panel framing and single-column fallback now adapt to the current window dimensions instead of the startup size.
- Upgraded the SDL visuals again so top-down occupants/features and `Depth 3D` billboards now use patterned pixel sprites with shadows instead of only solid color rectangles.
- Added the adventure editor flow to the SDL frontend: pressing `M` now raises the same confirmation prompt concept used by the native frontend.
- Added a shared-session regression test for editor targeting so the SDL/editor integration keeps using the selected adventure on title screens and the active adventure during a live run.
- Added a backend-neutral `AdventureEditorSession` snapshot layer and moved editor canvas overlay colors out of `AdventureEditorStore`, so the editor state is less tied to SwiftUI and easier to drive from an eventual SDL-native editor.
- Replaced the SDL branch's editor fallback with a first SDL-native in-window editor shell: the `M` prompt now opens an SDL editor mode with cursor movement, tool application, validation, saving, map cycling, and return-to-game flow.
- Tightened the SDL editor UX after live testing: the editor now has clearly distinct blue/cyan chrome instead of blending into the gameplay HUD, and `X` exits editor mode back to the game instead of quitting the application.
- Extended the SDL editor past map work: the non-spatial content tabs now have cycle-based in-window editing for dialogue, quest stages, encounters, shops, NPCs, and enemies instead of being view-only dead ends.
- Installed the local Windows cross-toolchain pieces `mingw-w64` and `zig`, and verified `x86_64-w64-mingw32-gcc` can emit a real x86_64 PE executable. The remaining missing piece for actual Swift-to-Windows builds is still a Windows Swift SDK bundle.
- Kept the native macOS path intact while starting the portability cleanup: `GameApp` now only calls the native launcher/editor on platforms that have them, and shared editor files no longer import AppKit/SwiftUI when they do not actually need those frameworks.
- Split the shared depth math out of the native SwiftUI renderer: `DepthRaycaster` and its sample types no longer depend on `CGPoint` or `CoreGraphics`, and the AppKit-only depth presentation types are fenced back into the native layer.
- Added platform guards around the native AppKit frontend files, made the terminal/sound/runtime helpers compile without hard `Darwin` or `AVFoundation` assumptions, and added a first Windows GitHub Actions SDL build lane that installs Swift plus the SDL3 VC SDK on a Windows runner.
- The first Windows CI run proved the workflow path is live; it failed at Swift installation, and the branch is now pointed at the available Swift 6.3 Windows development snapshot (`2026-02-27-a`) instead of the missing 6.3 release installer.
- The next Windows failure was real progress: the 6.3 snapshot installed and reached `swift build`, then died because the MSVC CRT libraries were not on the linker path while compiling the manifest. The workflow now explicitly loads the Visual Studio developer environment before building.
- The next Windows failure after that was a Swift frontend crash during optimization of `GameApp.runTerminal()`. Since the Windows target is SDL-first, `runTerminal()` is now stubbed out on Windows so that code path does not participate in the Win64 build.

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
- The editor and graphics shells now intentionally use `ViewThatFits` plus scroll-backed fallbacks; keep future panel additions responsive instead of adding more fixed-width rows.
- The remaining refactor hotspots have shifted to `AdventureEditorStore+Helpers.swift`, `AdventureEditorRootView+Panels.swift`, and `GraphicsGameUI.swift`; future passes should keep extracting by behavior-specific helpers and dedicated subviews instead of rebuilding large mixed-purpose files.
- The SDL branch is intentionally local-only for now; do not push it until the renderer is stable enough that missing AppKit parity will not confuse the public repo.
- The SDL frontend currently links against the locally installed `sdl3` Homebrew package and emits a linker warning because the Homebrew bottle was built for a newer host SDK than the package's declared macOS target.
- The shared scene snapshot is now the correct seam for future renderer work; continue moving rendering decisions out of SwiftUI views and into snapshot-to-pixels adapters.
- The intended product split is now explicit: native AppKit stays the preferred macOS frontend, while SDL is the parity/cross-platform path that should eventually become the real Windows/Linux graphics frontend.
- SDL still needs more fidelity work, but it is now much closer to a true second frontend and less of a diagnostic shell: text, layout, and sprite reads are no longer the most glaring parity gaps.
- The SDL branch now has a real in-window editor shell, but it is still a focused first pass: the spatial map workflow is there, while the richer non-spatial content panels from the native editor are not fully ported yet.
- The SDL branch now covers both spatial and non-spatial editor workflows, but it still uses cycle-based editing rather than true text entry for authored content fields.
- The next SDL/editor move should add proper text entry for authored strings in the SDL editor so those tabs are not limited to curated template cycles.
- The codebase now has a first compile-surface split via platform fences; the next portability move is validating the Windows runner and, if it still hits package-graph issues, tightening that into a stricter target-level split.

## Next Build Targets

- Expand the graphical combat feedback so hits, damage, and danger states are more legible.
- Continue expanding the world/content so the current slice grows toward the full multi-phase plan.
- Commit stable checkpoints frequently now that git is part of the workflow.
- Add more authored map events, optional treasure loops, and denser region-specific enemy encounters.
- Build a full scripted playthrough using the bridge so progression can be regression-tested end to end.
- Expand the external pack format so third-party adventures can define custom quest flags and bespoke item tables, not just reuse the built-in systems.
- Continue the SDL branch by adding real low-res bitmap font rendering, proper sprite-pattern drawing, and layout scaling based on live window size instead of the current fixed frame.
- Keep pushing SDL toward native feature parity on macOS before attempting the first real Linux/Win64 build path.
- The next SDL parity pass should focus on denser tile-surface art, fewer hardcoded spacing constants, and then fixing any real Windows-runner fallout from the new CI lane.
- Local CrossOver testing on macOS proved the first successful Windows artifact was still incomplete: the EXE imports Swift runtime DLLs (`swiftCore.dll`, `Foundation.dll`, etc.), so the Windows CI packaging step now needs to bundle runtime DLLs from both the release folder and `swiftc -print-target-info` runtime paths.

- Windows SDL crash under Wine traced to Foundation UserDefaults in GraphicsPreferenceStore.loadTheme(); switched Windows theme persistence to a simple JSON file under Application Support while keeping macOS on UserDefaults.
- The SDL cross-platform branch is ready to merge: `windows-builds/` is now ignored locally, and the Windows SDL workflow is set to run from `main` pushes (plus manual dispatch) rather than PR branch updates.
- `main` now also has a dedicated macOS packaging workflow so GitHub can produce fresh app/CLI zips on each `main` push; future public releases can pull both Win64 and macOS artifacts directly from Actions.
- The first macOS Actions run failed because `macos-14` defaulted to Swift 5.10; the workflow now bootstraps the same Swift 6.3 snapshot family used by the Windows lane before packaging.
- The second macOS Actions run exposed stricter Swift 6.3 actor-isolation checks in the native SwiftUI layer; the affected editor/game root views are now explicitly `@MainActor`, matching the `@MainActor` stores/controllers they observe.
- The macOS workflow now explicitly pins `gha-setup-swift` to `build_arch: arm64`; relying on the action default (`amd64`) on `macos-14` was the wrong assumption and makes the runner setup ambiguous.
- After publishing `v0.2.0`, both CI packaging lanes were narrowed to `workflow_dispatch` plus `v*` tag pushes only; normal `main` commits should no longer trigger full macOS/Windows rebuilds.
