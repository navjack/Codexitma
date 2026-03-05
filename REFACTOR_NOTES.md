# Refactor Notes

These notes track the modularization work that was done to reduce edit-time context pressure by breaking large Swift files into smaller modules without changing runtime behavior.

## Completed Splits

- Model layer:
  - `Sources/Game/Model/CoreTypes.swift`
  - `Sources/Game/Model/AdventureWorldModels.swift`
  - `Sources/Game/Model/RuntimeModels.swift`

- Graphics app:
  - `Sources/Game/App/GraphicsRuntime.swift`
  - `Sources/Game/App/GraphicsGameUI.swift`
  - `Sources/Game/App/GraphicsGameUI+Screens.swift`
  - `Sources/Game/App/GraphicsGameUI+Panels.swift`
  - `Sources/Game/App/GraphicsGameUI+Support.swift`
  - `Sources/Game/App/GraphicsSceneSnapshot.swift`
  - `Sources/Game/App/GraphicsSceneSnapshot+Builder.swift`
  - `Sources/Game/App/GraphicsSceneSnapshot+Lighting.swift`
  - `Sources/Game/App/SDLGraphicsLauncher.swift`
  - `Sources/Game/App/SDLGraphicsLauncher+Input.swift`
  - `Sources/Game/App/SDLGraphicsLauncher+SceneRendering.swift`
  - `Sources/Game/App/SDLGraphicsLauncher+DepthRendering.swift`
  - `Sources/Game/App/SDLGraphicsLauncher+Support.swift`
  - `Sources/Game/App/MapBoardView.swift`
  - `Sources/Game/App/MapBoardView+DepthRendering.swift`
  - `Sources/Game/App/MapBoardView+DepthAppearance.swift`
  - `Sources/Game/App/MapBoardView+DepthSupport.swift`
  - `Sources/Game/App/DepthRaycasting.swift`
  - `Sources/Game/App/GraphicsTileViews.swift`
  - `Sources/Game/App/GraphicsSupport.swift`

- Editor:
  - `Sources/Game/App/AdventureEditorWindowing.swift`
  - `Sources/Game/App/AdventureEditorTypes.swift`
  - `Sources/Game/App/AdventureEditorStore.swift`
  - `Sources/Game/App/AdventureEditorStore+Document.swift`
  - `Sources/Game/App/AdventureEditorStore+Canvas.swift`
  - `Sources/Game/App/AdventureEditorStore+ContentEditors.swift`
  - `Sources/Game/App/AdventureEditorStore+Helpers.swift`
  - `Sources/Game/App/AdventureEditorContent.swift`
  - `Sources/Game/App/AdventureEditorUI.swift`
  - `Sources/Game/App/AdventureEditorChromeViews.swift`
  - `Sources/Game/App/AdventureEditorRootView+Shell.swift`
  - `Sources/Game/App/AdventureEditorRootView+Panels.swift`
  - `Sources/Game/App/AdventureEditorRootView+Inspector.swift`
  - `Sources/Game/App/AdventureEditorRootView+Helpers.swift`
  - `Sources/Game/App/AdventureEditorStyle.swift`

- Engine:
  - `Sources/Game/Engine/GameEngine.swift`
  - `Sources/Game/Engine/GameEngine+Modes.swift`
  - `Sources/Game/Engine/GameEngine+Pause.swift`
  - `Sources/Game/Engine/GameEngine+WorldFlow.swift`
  - `Sources/Game/Engine/GameEngine+InventoryAdventure.swift`
  - `Sources/Game/Engine/GameEngine+QueriesShop.swift`

- Tests:
  - `Tests/GameTests/CoreGameTests.swift`
  - `Tests/GameTests/ContentPipelineTests.swift`
  - `Tests/GameTests/EditorWorkflowTests.swift`

## Remaining Hotspots

- `Sources/Game/App/SDLGraphicsLauncher+DepthRendering.swift`
  - Now the biggest SDL-specific graphics file.
  - Best next split: pull editor-overlay color helpers and board-only pattern helpers away from the depth floor/wall renderer, or extract shared projection math with the native depth path.

- `Sources/Game/App/MapBoardView+DepthSupport.swift`
  - Still broad because it mixes billboard queries, corridor fallback, projection math, world lookup helpers, and region-theme resolution.
  - Best next split: separate projection/world-query helpers from region-theme resolution if native depth work keeps growing.

- `Sources/Game/App/AdventureEditorStore+Helpers.swift`
  - Still broad because it mixes selection helpers, editor placement factories, color helpers, and blank-pack builders.
  - Best next split: separate editor selection/computed accessors from pack factory utilities.

- `Sources/Game/App/AdventureEditorRootView+Panels.swift`
  - Still large because it owns most content-specific panel layouts in one file.
  - Best next split: extract standalone panel views (`DialoguePanels`, `EncounterPanels`, `ShopPanels`, etc.).

## Refactor Rule

When moving code across files, watch for file-scoped access:

- `private` and `fileprivate` often become invalid after a split.
- Prefer keeping behavior the same and only widening visibility to internal when a cross-file move requires it.
- Re-run `swift test` after each extraction step.
