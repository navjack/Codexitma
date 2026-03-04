# Refactor Notes

This branch exists to reduce edit-time context pressure by breaking large Swift files into smaller modules without changing runtime behavior.

## Completed Splits

- Model layer:
  - `Sources/Game/Model/CoreTypes.swift`
  - `Sources/Game/Model/AdventureWorldModels.swift`
  - `Sources/Game/Model/RuntimeModels.swift`

- Graphics app:
  - `Sources/Game/App/GraphicsRuntime.swift`
  - `Sources/Game/App/GraphicsGameUI.swift`
  - `Sources/Game/App/MapBoardView.swift`
  - `Sources/Game/App/DepthRaycasting.swift`
  - `Sources/Game/App/GraphicsTileViews.swift`
  - `Sources/Game/App/GraphicsSupport.swift`

- Editor:
  - `Sources/Game/App/AdventureEditorWindowing.swift`
  - `Sources/Game/App/AdventureEditorTypes.swift`
  - `Sources/Game/App/AdventureEditorStore.swift`
  - `Sources/Game/App/AdventureEditorContent.swift`
  - `Sources/Game/App/AdventureEditorUI.swift`
  - `Sources/Game/App/AdventureEditorStyle.swift`

- Tests:
  - `Tests/GameTests/CoreGameTests.swift`
  - `Tests/GameTests/ContentPipelineTests.swift`
  - `Tests/GameTests/EditorWorkflowTests.swift`

## Remaining Hotspots

- `Sources/Game/App/AdventureEditorStore.swift`
  - Still large because it owns most editor mutation behavior.
  - Best next split: extract behavior-specific extensions (selection, canvas placement, content editing, save/export flow).

- `Sources/Game/App/AdventureEditorUI.swift`
  - Still large because the root editor view owns many panels.
  - Best next split: extract major panels into standalone `View` types (`MapWorkbenchPanel`, `DialogueEditorPanel`, `ShopEditorPanel`, etc.).

- `Sources/Game/Engine/GameEngine.swift`
  - Still a single large type.
  - Best next split: extensions by state domain (`title/creation`, `exploration`, `inventory/shop`, `combat`, `persistence`).

## Refactor Rule

When moving code across files, watch for file-scoped access:

- `private` and `fileprivate` often become invalid after a split.
- Prefer keeping behavior the same and only widening visibility to internal when a cross-file move requires it.
- Re-run `swift test` after each extraction step.
