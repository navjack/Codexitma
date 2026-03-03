# Automation And Remote Control

`Codexitma` now supports a built-in headless control surface for testing and external tooling.

## Script Mode

Run a fixed command sequence and print JSON state:

```sh
./Codexitma --script "new, e, right, right, state"
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
