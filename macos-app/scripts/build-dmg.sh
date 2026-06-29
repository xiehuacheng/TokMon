#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="TokMon"
RELEASE_DIR="$APP_ROOT/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_ROOT/Packaging/Info.plist")
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found: $APP_BUNDLE" >&2
    echo "Run scripts/build-app.sh first." >&2
    exit 1
fi

TMP_DMG=$(mktemp -d)
trap 'rm -rf "$TMP_DMG"' EXIT

cp -a "$APP_BUNDLE" "$TMP_DMG/"

# Remove Finder metadata that breaks strict code signature validation.
find "$TMP_DMG" -name ".DS_Store" -delete
find "$TMP_DMG" -print0 | while IFS= read -r -d '' entry; do
    xattr -d com.apple.FinderInfo "$entry" 2>/dev/null || true
done

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$TMP_DMG" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Built $DMG_PATH"
shasum -a 256 "$DMG_PATH"
