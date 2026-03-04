#!/bin/zsh

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-dev}
DIST_DIR="$ROOT_DIR/dist/$VERSION"

cd "$ROOT_DIR"

swift build -c release

BIN_PATH=$(swift build -c release --show-bin-path)
BUILD_BIN="$BIN_PATH/Game"
RESOURCE_BUNDLE="$BIN_PATH/Game_Game.bundle"

if [[ ! -x "$BUILD_BIN" ]]; then
    echo "Missing release binary at $BUILD_BIN" >&2
    exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Missing resource bundle at $RESOURCE_BUNDLE" >&2
    exit 1
fi

APP_DIR="$DIST_DIR/Codexitma.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
CLI_DIR="$DIST_DIR/Codexitma-cli"

rm -rf "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$CLI_DIR"

cp "$BUILD_BIN" "$APP_MACOS/Codexitma"
chmod +x "$APP_MACOS/Codexitma"

# SwiftPM's generated Bundle.module accessor looks for Game_Game.bundle
# under Bundle.main.bundleURL, so keep a copy at the app bundle root.
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Game_Game.bundle"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/Game_Game.bundle"

cat > "$APP_CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Codexitma</string>
    <key>CFBundleIdentifier</key>
    <string>com.navjack.codexitma</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codexitma</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

perl -0pi -e "s/__VERSION__/$VERSION/g" "$APP_CONTENTS/Info.plist"

cp "$BUILD_BIN" "$CLI_DIR/Codexitma"
chmod +x "$CLI_DIR/Codexitma"
cp -R "$RESOURCE_BUNDLE" "$CLI_DIR/Game_Game.bundle"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/Codexitma-macOS-app.zip"
ditto -c -k --keepParent "$CLI_DIR" "$DIST_DIR/Codexitma-macOS-cli.zip"

cp "$APP_MACOS/Codexitma" "$ROOT_DIR/Codexitma"

echo "Created:"
echo "  $DIST_DIR/Codexitma-macOS-app.zip"
echo "  $DIST_DIR/Codexitma-macOS-cli.zip"
