#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

SCRIPT_FILE="$ROOT_DIR/scripts/readme_screenshots.txt"
SCREENSHOT_DIR="$ROOT_DIR/screenshots"
NATIVE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/codexitma-native-shots.XXXXXX")
SDL_TMP=$(mktemp -d "${TMPDIR:-/tmp}/codexitma-sdl-shots.XXXXXX")

cleanup() {
    rm -rf "$NATIVE_TMP" "$SDL_TMP"
}
trap cleanup EXIT

echo "Building Codexitma..."
swift build

BUILD_BINARY=""
for candidate in \
    "$ROOT_DIR/.build/arm64-apple-macosx/debug/Game" \
    "$ROOT_DIR/.build/debug/Game"
do
    if [[ -x "$candidate" ]]; then
        BUILD_BINARY="$candidate"
        break
    fi
done

if [[ -z "$BUILD_BINARY" ]]; then
    echo "Could not find a built Game binary under .build/" >&2
    exit 1
fi

cp "$BUILD_BINARY" "$ROOT_DIR/Codexitma"
mkdir -p "$SCREENSHOT_DIR"

echo "Capturing native README screenshots..."
CODEXITMA_SCREENSHOT_DIR="$NATIVE_TMP" \
    "$BUILD_BINARY" --graphics-script-file "$SCRIPT_FILE"

echo "Capturing SDL README screenshots..."
CODEXITMA_SCREENSHOT_DIR="$SDL_TMP" \
    "$BUILD_BINARY" --sdl --graphics-script-file "$SCRIPT_FILE"

copy_latest() {
    local source_dir=$1
    local pattern=$2
    local destination=$3

    local match
    match=$(find "$source_dir" -maxdepth 1 -type f -name "$pattern" | sort | tail -n 1)
    if [[ -z "$match" ]]; then
        echo "Missing screenshot matching $pattern in $source_dir" >&2
        exit 1
    fi

    cp "$match" "$destination"
}

copy_latest "$NATIVE_TMP" "native-*-title-ashesofmerrow.png" \
    "$SCREENSHOT_DIR/native-title-ashesofmerrow.png"
copy_latest "$SDL_TMP" "sdl-*-title-ashesofmerrow.png" \
    "$SCREENSHOT_DIR/sdl-title-ashesofmerrow.png"

copy_latest "$NATIVE_TMP" "native-*-creator-warden.png" \
    "$SCREENSHOT_DIR/native-creator-warden.png"
copy_latest "$SDL_TMP" "sdl-*-creator-warden.png" \
    "$SCREENSHOT_DIR/sdl-creator-warden.png"

copy_latest "$NATIVE_TMP" "native-*-ashesofmerrow-merrow_village-exploration-view-a.png" \
    "$SCREENSHOT_DIR/native-ashesofmerrow-merrow-village-view-a.png"
copy_latest "$SDL_TMP" "sdl-*-ashesofmerrow-merrow_village-exploration-view-a.png" \
    "$SCREENSHOT_DIR/sdl-ashesofmerrow-merrow-village-view-a.png"

copy_latest "$NATIVE_TMP" "native-*-ashesofmerrow-merrow_village-exploration-view-b.png" \
    "$SCREENSHOT_DIR/native-ashesofmerrow-merrow-village-view-b.png"
copy_latest "$SDL_TMP" "sdl-*-ashesofmerrow-merrow_village-exploration-view-b.png" \
    "$SCREENSHOT_DIR/sdl-ashesofmerrow-merrow-village-view-b.png"

echo "Updated README screenshots in $SCREENSHOT_DIR"
