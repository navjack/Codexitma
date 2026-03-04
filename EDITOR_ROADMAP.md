# Codexitma Editor Roadmap

This document captures the current state of the in-game adventure editor, the real data model it sits on top of, and the next implementation targets required to turn it into a full authoring suite.

It should be treated as the editor-specific companion to `PLAN.md`, not a replacement for it.

## Current State

The editor exists today as a usable foundation, not a finished content pipeline.

Entry point:

- Launch with `--editor`
- Primary implementation lives in `Sources/Game/App/AdventureEditorUI.swift`

What it can do right now:

- Load a bundled or external adventure into an editable in-memory document
- Create a blank template adventure document
- Edit adventure metadata:
  - folder name
  - adventure id
  - title
  - intro line
  - summary
- Add maps
- Duplicate maps
- Edit map id and map name
- Paint terrain tiles on the active map from a fixed tile palette
- Switch between explicit tool modes:
  - `Terrain`
  - `NPC`
  - `Enemy`
  - `Interactable`
  - `Portal`
  - `Spawn`
  - `Erase`
  - `Select`
- Place layered NPC, enemy, interactable, portal, and spawn data directly on the map canvas
- Select placed objects on the canvas and inspect them in a right-side panel
- Perform a first pass of inspector editing for:
  - NPC ids, names, and dialogue ids
  - Enemy ids, names, and core combat stats
  - Interactable ids, titles, and kinds
  - Portal destination map retargeting
- Export a full external content pack into `~/Library/Application Support/Codexitma/Adventures`

## Current Export Behavior

The current editor exports a full pack layout, not only map data.

Files written on export:

- `adventure.json`
- `quest_flow.json`
- `world.json`
- `dialogues.json`
- `encounters.json`
- `npcs.json`
- `enemies.json`
- `shops.json`
- `maps/<map-id>.txt`

Current blank-template defaults:

- One starter map
- One sample quest stage
- Empty arrays for dialogues, encounters, NPCs, enemies, and shops unless the editor started from an existing adventure

## What Is Already Correct

The current direction is fundamentally right:

- The editor creates a full externalized content pack
- New packs can be authored outside the app bundle
- External packs can override bundled adventures when they share the same adventure id
- Terrain editing is already visual instead of text-only
- The editor is working on top of the same JSON pack structure that the runtime now loads

This means the editor already has the correct high-level shape for future expansion.

## What Is Not Yet Implemented

The current UI does not yet expose most of the authored content model.

Missing GUI authoring features:

- Dialogue editing
- Quest-stage editing
- Encounter-table editing
- Shop editing
- Assigning a shop to an NPC
- Assigning flags, rewards, or quest hooks through an inspector
- Editing portal coordinates directly beyond map-retargeting
- Rich inspector editing for:
  - quest flag requirements
  - quest flag grants
  - reward items
  - reward marks
  - merchant bindings
  - AI settings
- Visual list management for non-map records such as dialogues, encounters, and shops

Right now, those structures exist in the editor document and exporter, but most of them are not editable through the GUI.

## Data Model Truth

This distinction matters for the editor design:

- Terrain is stored in the map text file layer
- NPCs, enemies, shops, and most interactables are not terrain
- Those entities are separate coordinate-based records layered on top of the map

That means the correct editing model is not "everything is a painted tile."

The correct editing model is:

- Paint terrain into the tile layer
- Place entities onto coordinates using dedicated tools
- Edit entity properties through an inspector
- Serialize terrain and placed entities back into their appropriate JSON or map files

## Target Editor Behavior

When creating a new adventure, the editor should produce named template versions of every supported content file with valid starter data, not sparse placeholders.

Each new pack should include:

- A valid `adventure.json` manifest
- A starter `world.json` with at least one region and one map reference
- A starter `quest_flow.json` with example stage data
- Example `dialogues.json` entries
- Example `encounters.json` entries
- Example `npcs.json` entries
- Example `enemies.json` entries
- Example `shops.json` entries
- At least one starter `maps/*.txt` file

The GUI should then allow a designer to create or edit everything defined in those files without hand-editing JSON.

## Required Editor Modes

The map view should grow into explicit tool modes.

Planned tool modes:

- `Terrain`
- `NPC`
- `Enemy`
- `Interactable`
- `Portal`
- `Spawn`
- `Erase`
- `Select`

Expected behavior:

- `Terrain`: paint floor, walls, water, brush, doors, shrine/beacon/stairs, and future tile families
- `NPC`: place NPC records and open an inspector for name, dialogue id, merchant id, and quest hooks
- `Enemy`: place enemy records and open an inspector for enemy type, encounter id, and behavior metadata
- `Interactable`: place coordinate-based world objects and assign triggers or rewards
- `Portal`: define exits between maps and regions
- `Spawn`: define player entry points and special spawn anchors
- `Erase`: remove the currently targeted entity or tile
- `Select`: inspect and edit existing authored objects without placing new ones

## Required Inspector System

The editor needs a property inspector so placed objects can be fully authored.

Minimum inspector fields:

- Shared:
  - id
  - map id
  - x / y position
  - display label
- NPC:
  - dialogue id
  - merchant id
  - quest flags granted
  - quest flags required
- Enemy:
  - enemy id
  - encounter id
  - respawn or one-shot behavior
- Interactable:
  - trigger type
  - required item id
  - required flag
  - reward item id
  - reward marks
- Portal:
  - destination map id
  - destination x / y
- Shops:
  - stock list
  - prices
  - one-time or repeatable offers

## Required Data Tabs

Beyond the map canvas, the editor should expose the non-spatial content as first-class tabs.

Planned tabs:

- `Maps`
- `Dialogues`
- `Quest Flow`
- `Encounters`
- `NPCs`
- `Enemies`
- `Shops`
- `Adventure`

Why this split matters:

- Some data is spatial and best authored on the map
- Some data is list-based and better managed in structured tables
- The editor should support both workflows cleanly

## Content Pipeline Direction

The editor should remain aligned with the current external pack system.

Recommended rules:

- The editor should always write full packs, not partial proprietary project files
- An exported pack should be immediately loadable by the game
- Keeping the same adventure id should continue to act as a mod/override for a bundled adventure
- Changing the adventure id should create a distinct standalone adventure
- The editor should validate cross-file references before export

Required validation examples:

- Every map referenced by `world.json` must exist
- Every `dialogue id` assigned to an NPC must exist in `dialogues.json`
- Every `merchant id` assigned to an NPC must exist in `shops.json`
- Every referenced item id must exist in the item catalog
- Every portal destination must point to a valid map and coordinate

## Recommended Near-Term Milestones

### Milestone 1: Object Placement

Status:

- Implemented

- Add `Terrain`, `NPC`, `Enemy`, `Interactable`, `Portal`, `Spawn`, `Erase`, and `Select` tool modes
- Add visual placement and deletion for layered entities
- Add selection outlines and coordinate readouts

### Milestone 2: Inspector

Status:

- In progress

- Add a right-side inspector panel
- Allow editing of the selected object's fields
- Wire inspector edits directly into the in-memory document model

### Milestone 3: Data Tabs

- Add editable list/table views for dialogues, quest flow, encounters, and shops
- Support creating, deleting, and renaming content ids safely
- Add reference pickers instead of free-form id typing where practical

### Milestone 4: Template Quality

- Upgrade blank-pack generation so new adventures ship with meaningful example records across all supported files
- Make starter templates self-consistent and immediately playable

### Milestone 5: Live Playtest

- Add an editor-side "Playtest" button
- Export to a temp or staging pack
- Launch directly into the selected adventure without leaving the editor

## Non-Goals For The First Editor Push

These would be useful later, but they should not block the current editor expansion:

- Collaborative multi-user editing
- Binary project formats
- Custom sprite import pipelines
- Full diff/patch mod authoring
- Visual scripting beyond the current JSON-driven content model

## Summary

The editor is already a real starting point, but it is still primarily a terrain and metadata tool.

To become the full adventure-authoring system Codexitma needs, it must evolve from:

- "map painter that exports packs"

into:

- "complete graphical authoring suite for all supported adventure data"

The next build targets are straightforward:

1. Add object placement tools.
2. Add an inspector.
3. Add non-spatial data tabs.
4. Improve starter templates.
5. Add live playtesting.
