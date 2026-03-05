# Automation And Remote Control

`Codexitma` now supports a built-in headless control surface for testing and external tooling.

It also supports a graphics automation path for deterministic screenshot capture in the real native and SDL frontends.

## Script Mode

Run a fixed command sequence and print JSON state:

```sh
./Codexitma --script "new, e, right, right, state"
```

Select the second adventure before starting:

```sh
./Codexitma --script "right, new, e, state"
```

Add `--step-json` to emit a JSON snapshot after every command:

```sh
./Codexitma --script "new, e, right" --step-json
```

You can also load commands from a file:

```sh
./Codexitma --script-file ./path/to/run.txt --step-json
```

Supported command tokens:

- `new`
- `load`
- `save`
- `up` / `down` / `left` / `right`
- `w` / `a` / `s` / `d`
- `interact` / `act` / `talk` / `e`
- `inventory` / `item` / `i`
- `help` / `hint` / `goal` / `j`
- `cancel` / `q`
- `quit` / `x`
- `state`
- `reset`
- `warp:<x>:<y>`
- `warp:<x>:<y>:<facing>`
- `warp:<mapID>:<x>:<y>`
- `warp:<mapID>:<x>:<y>:<facing>`
  - aliases: `goto`, `teleport`, `tp`
  - facings: `n/u/up`, `s/down`, `w/l/left`, `e/r/right`

During an active run, `cancel` / `q` now opens the in-game pause/menu state. Use `quit` / `x` when the script should request a full app quit instead of a menu transition.

Coordinate warp examples:

```sh
./Codexitma --script "new,e,warp:merrow_village:10:5:w,state"
./Codexitma --script "new,e,warp:merrow_village:12:5:e,state" --step-json
```

Lighting checkpoint baseline script:

```sh
./Codexitma --script-file ./scripts/lighting_checkpoints_ashes.txt --step-json
```

## Graphics Script Mode

Run the actual graphics frontend with one scripted input per frame:

```sh
./Codexitma --graphics-script-file ./scripts/readme_screenshots.txt
./Codexitma --sdl --graphics-script-file ./scripts/readme_screenshots.txt
```

Graphics script mode accepts normal gameplay tokens plus:

- `shot`
- `shot:<label>`
- `theme`
- `style`
- `theme:gemstone`
- `theme:ultima`
- `theme:depth3d`

If `CODEXITMA_SCREENSHOT_DIR` is set, screenshot output is redirected there instead of the normal per-user screenshots folder. That is the intended path for reproducible README gallery refreshes.

To rebuild the stable README image set after visual changes:

```sh
./scripts/update_readme_screenshots.sh
```

That script is intended to be rerun whenever renderer-facing UI or visual output changes so the checked-in README gallery stays aligned with the current build.

## Bridge Mode

Run an interactive JSON bridge over stdio:

```sh
./Codexitma --bridge
```

Then send plain command tokens on stdin, one line at a time:

```text
new
e
right
state
```

The game emits one JSON line per accepted input. This is intended as the easiest control surface to wrap in an MCP server later if you want Codex to connect through a manually-added server.

Snapshots now include `adventureID`, `marks`, and active shop data (`shopTitle`, `shopOffers`), so automation can tell which campaign is loaded and what a merchant currently offers.

The automation bridge exercises the same data-driven content packs that the interactive game uses, so scripted runs are a good way to validate changes made in [ContentData](/Volumes/4terrybi/coding/Codexitma/Sources/Game/ContentData) without touching engine code.
