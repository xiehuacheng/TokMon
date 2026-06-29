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

# Sign the DMG for Sparkle's EdDSA verification.
SIGN_UPDATE_BIN="${TOKMON_SPARKLE_SIGN_UPDATE:-}"
if [[ -z "$SIGN_UPDATE_BIN" ]] || [[ ! -x "$SIGN_UPDATE_BIN" ]]; then
    SIGN_UPDATE_BIN="$APP_ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
fi
if [[ ! -x "$SIGN_UPDATE_BIN" ]]; then
    SIGN_UPDATE_BIN="$(command -v sign_update || true)"
fi

PRIVATE_KEY="${TOKMON_SPARKLE_PRIVATE_KEY:-$HOME/.config/tokmon-release/sparkle-ed25519-private.pem}"
SPARKLE_SIGNATURE=""
if [[ -x "$SIGN_UPDATE_BIN" ]] && [[ -f "$PRIVATE_KEY" ]]; then
    SPARKLE_SIGNATURE=$("$SIGN_UPDATE_BIN" "$DMG_PATH" --ed-key-file "$PRIVATE_KEY" -p 2>/dev/null || true)
fi

DMG_SIZE=$(stat -f%z "$DMG_PATH")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_ROOT/Packaging/Info.plist")
DOWNLOAD_URL="https://github.com/xiehuacheng/TokMon/releases/download/v$VERSION/$(basename "$DMG_PATH")"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"

if [[ -n "$SPARKLE_SIGNATURE" ]]; then
    cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>TokMon Changelog</title>
    <link>https://github.com/xiehuacheng/TokMon/releases</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>TokMon $VERSION</title>
      <pubDate>$(date -R)</pubDate>
      <link>https://github.com/xiehuacheng/TokMon/releases/tag/v$VERSION</link>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="$DOWNLOAD_URL"
                 length="$DMG_SIZE"
                 type="application/x-apple-diskimage"
                 sparkle:edSignature="$SPARKLE_SIGNATURE" />
    </item>
  </channel>
</rss>
EOF
    echo "Generated $APPCAST_PATH"
    echo "Sparkle EdDSA signature: $SPARKLE_SIGNATURE"
else
    echo "Warning: DMG was not signed for Sparkle (sign_update or private key missing)." >&2
fi

echo "Built $DMG_PATH"
shasum -a 256 "$DMG_PATH"
