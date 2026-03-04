#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

TAG=${1:-}
if [[ -z "$TAG" ]]; then
    TAG=$(gh release view --json tagName --jq '.tagName')
fi

DIST_DIR="$ROOT_DIR/dist/${TAG}-assets"
MACOS_DIR="$DIST_DIR/macos"
WIN_ZIP="$DIST_DIR/Codexitma-win64.zip"
WIN_DIR="$DIST_DIR/Codexitma-win64"

mkdir -p "$MACOS_DIR" "$WIN_DIR"

gh release download "$TAG" --pattern "Codexitma-macOS-*.zip" --dir "$MACOS_DIR" --clobber
gh release download "$TAG" --pattern "Codexitma-win64.zip" --dir "$DIST_DIR" --clobber

if [[ -f "$WIN_ZIP" ]]; then
    ditto -x -k "$WIN_ZIP" "$WIN_DIR"

    # GitHub's Windows artifact zip contains a top-level "windows" folder.
    # Mirror the older local dist layout by flattening a copy of that payload.
    if [[ -d "$WIN_DIR/windows" ]]; then
        cp -R "$WIN_DIR/windows/." "$WIN_DIR/"
    fi
fi

echo "Synced release $TAG into:"
echo "  $DIST_DIR"
