#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/.." && pwd)"
APP_NAME="TokMon"
RELEASE_DIR="$APP_ROOT/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

cd "$APP_ROOT"
swift build -c release

# Build and sign the bundle in a temporary directory first.  Finder may attach
# metadata (FinderInfo, .DS_Store) to the release directory while we work, and
# that metadata breaks strict code-signature verification.  Signing in /tmp
# avoids that race, then we copy the already-valid bundle into place.
TMP_BUILD=$(mktemp -d)
trap 'rm -rf "$TMP_BUILD"' EXIT
TMP_BUNDLE="$TMP_BUILD/$APP_NAME.app"
TMP_RESOURCES="$TMP_BUNDLE/Contents/Resources"

mkdir -p "$TMP_BUNDLE/Contents/MacOS"
mkdir -p "$TMP_RESOURCES"

cp "$APP_ROOT/.build/release/$APP_NAME" "$TMP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$APP_ROOT/Packaging/Info.plist" "$TMP_BUNDLE/Contents/Info.plist"
cp "$APP_ROOT/Assets/TokMon.icns" "$TMP_RESOURCES/TokMon.icns"

printf "APPL????" > "$TMP_BUNDLE/Contents/PkgInfo"

# Remove Finder metadata that breaks strict code signature validation.
find "$TMP_BUNDLE" -name ".DS_Store" -delete
find "$TMP_BUNDLE" -print0 | while IFS= read -r -d '' entry; do
    xattr -d com.apple.FinderInfo "$entry" 2>/dev/null || true
done

codesign --force --deep --sign - "$TMP_BUNDLE"
codesign --verify --deep --strict "$TMP_BUNDLE" >/dev/null

rm -rf "$APP_BUNDLE"
cp -a "$TMP_BUNDLE" "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
