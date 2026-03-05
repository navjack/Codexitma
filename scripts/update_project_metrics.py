#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "PROJECT_METRICS.md"


def run(*args: str) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def tracked_files() -> list[str]:
    return [line for line in run("git", "ls-files").splitlines() if line]


def line_count(path: str) -> int:
    try:
        with open(ROOT / path, "r", encoding="utf-8") as handle:
            return sum(1 for _ in handle)
    except Exception:
        return 0


def folder_swift_metrics(files: list[str], prefix: str) -> tuple[int, int]:
    subset = [path for path in files if path.endswith(".swift") and path.startswith(prefix)]
    return len(subset), sum(line_count(path) for path in subset)


def adventure_metrics() -> list[dict[str, int | str]]:
    packs_root = ROOT / "Sources/Game/ContentData/adventures"
    content_root = ROOT / "Sources/Game/ContentData"
    rows: list[dict[str, int | str]] = []

    for pack_path in sorted(packs_root.glob("*/*_pack.json")):
        pack = json.loads(pack_path.read_text(encoding="utf-8"))

        def resolve(name: str) -> Path:
            for base in (pack_path.parent, content_root):
                candidate = base / name
                if candidate.exists():
                    return candidate
            raise FileNotFoundError(name)

        world = json.loads(resolve(pack["worldFile"]).read_text(encoding="utf-8"))
        dialogues = json.loads(resolve(pack["dialoguesFile"]).read_text(encoding="utf-8"))
        encounters = json.loads(resolve(pack["encountersFile"]).read_text(encoding="utf-8"))
        npcs = json.loads(resolve(pack["npcsFile"]).read_text(encoding="utf-8"))
        enemies = json.loads(resolve(pack["enemiesFile"]).read_text(encoding="utf-8"))
        shops = json.loads(resolve(pack["shopsFile"]).read_text(encoding="utf-8"))
        objectives = json.loads(resolve(pack["objectivesFile"]).read_text(encoding="utf-8"))
        maps = world if isinstance(world, list) else world.get("maps", [])

        rows.append(
            {
                "adventure": pack_path.parent.name,
                "maps": len(maps),
                "interactables": sum(len(entry.get("interactables", [])) for entry in maps),
                "portals": sum(len(entry.get("portals", [])) for entry in maps),
                "dialogues": len(dialogues),
                "encounters": len(encounters),
                "npcs": len(npcs),
                "enemies": len(enemies),
                "shops": len(shops),
                "objectives": len(objectives),
            }
        )

    return rows


def cloc_metrics() -> dict:
    return json.loads(
        run(
            "cloc",
            "--vcs=git",
            "--exclude-dir=.build,dist,windows-builds",
            "--json",
            "--quiet",
            ".",
        )
    )


def cloc_value(metrics: dict, language: str, field: str) -> int:
    return int(metrics.get(language, {}).get(field, 0))


def build_document() -> str:
    files = tracked_files()
    swift_files = [path for path in files if path.endswith(".swift")]
    cloc = cloc_metrics()
    adventures = adventure_metrics()
    biggest = sorted(((line_count(path), path) for path in swift_files), reverse=True)[:5]

    git_commits = int(run("git", "rev-list", "--count", "HEAD"))
    snapshot_date = run("date", "+%B %-d, %Y")
    base_commit = run("git", "rev-parse", "--short", "HEAD")
    repo_size = run("du", "-sh", ".").split()[0]

    sources_swift_files, sources_swift_lines = folder_swift_metrics(files, "Sources/")
    tests_swift_files, tests_swift_lines = folder_swift_metrics(files, "Tests/")
    app_swift_files, app_swift_lines = folder_swift_metrics(files, "Sources/Game/App/")
    engine_swift_files, engine_swift_lines = folder_swift_metrics(files, "Sources/Game/Engine/")
    model_swift_files, model_swift_lines = folder_swift_metrics(files, "Sources/Game/Model/")
    content_swift_files, content_swift_lines = folder_swift_metrics(files, "Sources/Game/Content/")

    test_count = 0
    for path in files:
        if path.startswith("Tests/") and path.endswith(".swift"):
            test_count += (ROOT / path).read_text(encoding="utf-8").count("@Test")

    readme_screenshots = len(list((ROOT / "screenshots").glob("*.png")))

    adventure_by_name = {entry["adventure"]: entry for entry in adventures}
    ashes = adventure_by_name["ashes_of_merrow"]
    starfall = adventure_by_name["starfall_requiem"]

    return f"""# Project Metrics

This file is a living snapshot of `Codexitma` size, structure, and content metrics.

It is meant to answer practical questions such as:

- how large the codebase is
- where the complexity currently sits
- how much test coverage exists in terms of declared tests
- how much authored game content ships with the repo
- which files are becoming the next refactor pressure points

## Snapshot

- Snapshot date: `{snapshot_date}`
- Base commit: `{base_commit}`
- Measurement tools:
  - `cloc {cloc["header"]["cloc_version"]}`
  - `git`
  - `scripts/update_project_metrics.py`

## Headline Numbers

- Git commits: `{git_commits}`
- Git-tracked files: `{len(files)}`
- `cloc`-counted files: `{cloc["SUM"]["nFiles"]}`
- Repository size on disk: `{repo_size}`

## Code Size

- Total `cloc` code lines: `{cloc["SUM"]["code"]:,}`
- Total `cloc` blank lines: `{cloc["SUM"]["blank"]:,}`
- Total `cloc` comment lines: `{cloc["SUM"]["comment"]:,}`

### By Language

- Swift: `{cloc_value(cloc, "Swift", "nFiles")}` files, `{cloc_value(cloc, "Swift", "code"):,}` code lines
- JSON: `{cloc_value(cloc, "JSON", "nFiles")}` files, `{cloc_value(cloc, "JSON", "code"):,}` lines
- Markdown: `{cloc_value(cloc, "Markdown", "nFiles")}` files, `{cloc_value(cloc, "Markdown", "code"):,}` lines
- Shell: `{cloc_value(cloc, "Bourne Shell", "nFiles")}` files, `{cloc_value(cloc, "Bourne Shell", "code"):,}` lines
- YAML: `{cloc_value(cloc, "YAML", "nFiles")}` files, `{cloc_value(cloc, "YAML", "code"):,}` lines

### Raw Swift Line Counts

These are plain line counts rather than `cloc` code-line counts.

- Total Swift raw lines: `{sum(line_count(path) for path in swift_files):,}`
- Production Swift under `Sources/`: `{sources_swift_files}` files, `{sources_swift_lines:,}` lines
- Test Swift under `Tests/`: `{tests_swift_files}` files, `{tests_swift_lines:,}` lines

### Swift Breakdown By Area

- App/frontend/editor layer: `{app_swift_files}` files, `{app_swift_lines:,}` raw lines
- Engine layer: `{engine_swift_files}` files, `{engine_swift_lines:,}` raw lines
- Model layer: `{model_swift_files}` files, `{model_swift_lines:,}` raw lines
- Content loader layer: `{content_swift_files}` files, `{content_swift_lines:,}` raw lines

## Testing

- Declared tests: `{test_count}`

## Bundled Game Content

- Embedded adventures: `{len(adventures)}`
- Total bundled maps: `{sum(int(entry["maps"]) for entry in adventures)}`
- Total interactables: `{sum(int(entry["interactables"]) for entry in adventures)}`
- Total portals: `{sum(int(entry["portals"]) for entry in adventures)}`
- Total dialogue entries: `{sum(int(entry["dialogues"]) for entry in adventures)}`
- Total encounter definitions: `{sum(int(entry["encounters"]) for entry in adventures)}`
- Total NPC definitions: `{sum(int(entry["npcs"]) for entry in adventures)}`
- Total enemy definitions: `{sum(int(entry["enemies"]) for entry in adventures)}`
- Total shop definitions: `{sum(int(entry["shops"]) for entry in adventures)}`
- Total objective definition files: `{sum(int(entry["objectives"]) for entry in adventures)}`
- Stable README screenshots in repo: `{readme_screenshots}`

### Adventure Breakdown

- `Ashes of Merrow`
  - maps: `{ashes["maps"]}`
  - interactables: `{ashes["interactables"]}`
  - portals: `{ashes["portals"]}`
  - dialogues: `{ashes["dialogues"]}`
  - encounters: `{ashes["encounters"]}`
  - NPCs: `{ashes["npcs"]}`
  - enemies: `{ashes["enemies"]}`
  - shops: `{ashes["shops"]}`
  - objective files: `{ashes["objectives"]}`

- `Starfall Requiem`
  - maps: `{starfall["maps"]}`
  - interactables: `{starfall["interactables"]}`
  - portals: `{starfall["portals"]}`
  - dialogues: `{starfall["dialogues"]}`
  - encounters: `{starfall["encounters"]}`
  - NPCs: `{starfall["npcs"]}`
  - enemies: `{starfall["enemies"]}`
  - shops: `{starfall["shops"]}`
  - objective files: `{starfall["objectives"]}`

## Largest Swift Files

1. [{biggest[0][1]}]({ROOT / biggest[0][1]}): `{biggest[0][0]}` lines
2. [{biggest[1][1]}]({ROOT / biggest[1][1]}): `{biggest[1][0]}` lines
3. [{biggest[2][1]}]({ROOT / biggest[2][1]}): `{biggest[2][0]}` lines
4. [{biggest[3][1]}]({ROOT / biggest[3][1]}): `{biggest[3][0]}` lines
5. [{biggest[4][1]}]({ROOT / biggest[4][1]}): `{biggest[4][0]}` lines

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
"""


def main() -> None:
    OUTPUT.write_text(build_document(), encoding="utf-8")
    print(f"Updated {OUTPUT}")


if __name__ == "__main__":
    main()
