#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="AgentMon"
RELEASE_DIR="$APP_ROOT/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"

cd "$APP_ROOT"
swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$APP_ROOT/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$APP_ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_ROOT/Assets/AgentMon.icns" "$APP_BUNDLE/Contents/Resources/AgentMon.icns"
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Built $APP_BUNDLE"
