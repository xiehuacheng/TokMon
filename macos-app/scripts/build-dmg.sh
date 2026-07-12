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

BUILD_TMP=$(mktemp -d)
trap 'rm -rf "$BUILD_TMP"' EXIT

RW_DMG="$BUILD_TMP/tokmon-rw.dmg"
MOUNT_POINT="$BUILD_TMP/mount"
BACKGROUND_DIR="$MOUNT_POINT/.background"
BACKGROUND_IMG="$BACKGROUND_DIR/dmg-background.png"

# Create a blank read/write DMG big enough for the app plus some headroom.
APP_SIZE=$(du -sm "$APP_BUNDLE" | cut -f1)
DMG_SIZE_MB=$((APP_SIZE + 20))
hdiutil create -size "${DMG_SIZE_MB}m" -fs HFS+ -volname "$APP_NAME" -ov "$RW_DMG" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_POINT" -nobrowse >/dev/null
trap 'hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true; rm -rf "$BUILD_TMP"' EXIT

# Copy app bundle and create the familiar /Applications alias.
cp -a "$APP_BUNDLE" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

# Remove Finder metadata that can break strict code signature validation.
find "$MOUNT_POINT/$APP_NAME.app" -name ".DS_Store" -delete
find "$MOUNT_POINT/$APP_NAME.app" -print0 | while IFS= read -r -d '' entry; do
    xattr -d com.apple.FinderInfo "$entry" 2>/dev/null || true
done

# Generate a background image if PIL is available.
mkdir -p "$BACKGROUND_DIR"
if python3 -c "from PIL import Image, ImageDraw, ImageFont" >/dev/null 2>&1; then
    python3 - "$BACKGROUND_IMG" "$APP_NAME" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFont

output_path = sys.argv[1]
app_name = sys.argv[2]
width, height = 600, 400

# Subtle dark background matching the app's HUD aesthetic.
img = Image.new('RGB', (width, height), '#1c1c1e')
draw = ImageDraw.Draw(img)

# Try to load a system font; fall back to PIL's default if none are available.
font = None
for path, size in [
    ('/System/Library/Fonts/Helvetica.ttc', 24),
    ('/System/Library/Fonts/SFNSText.ttf', 24),
    ('/System/Library/Fonts/Supplemental/Arial.ttf', 24),
    ('/Library/Fonts/Arial.ttf', 24),
]:
    try:
        font = ImageFont.truetype(path, size)
        break
    except Exception:
        pass
if font is None:
    font = ImageFont.load_default()

text = f"Drag {app_name} to Applications"
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
draw.text(((width - text_width) // 2, 60), text, fill='#f2f2f7', font=font)

img.save(output_path)
PY
    chflags hidden "$BACKGROUND_DIR"

    # Arrange the icons and set the background via Finder/AppleScript.
    osascript >/dev/null 2>&1 <<EOF || true
        tell application "Finder"
            tell disk "$APP_NAME"
                open
                set current view of container window to icon view
                set toolbar visible of container window to false
                set statusbar visible of container window to false
                set the bounds of container window to {100, 100, 700, 500}
                set theViewOptions to icon view options of container window
                set arrangement of theViewOptions to not arranged
                set icon size of theViewOptions to 96
                set text size of theViewOptions to 12
                set background picture of theViewOptions to POSIX file "$BACKGROUND_IMG"
                set position of item "$APP_NAME.app" to {150, 180}
                set position of item "Applications" to {450, 180}
                update
                close
            end tell
        end tell
EOF
fi

hdiutil detach "$MOUNT_POINT" >/dev/null

# Convert to a compressed, read-only DMG.
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" >/dev/null

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
RELEASE_NOTES_NAME="release-notes.html"
RELEASE_NOTES_URL="https://github.com/xiehuacheng/TokMon/releases/download/v$VERSION/$RELEASE_NOTES_NAME"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
RELEASE_NOTES_PATH="$RELEASE_DIR/$RELEASE_NOTES_NAME"

# Generate a simple HTML release-notes page from the git log since the previous version tag.
PREV_TAG=$(git tag --sort=-v:refname | grep -v "^v${VERSION}$" | head -n1 || true)
if [[ -z "$PREV_TAG" ]]; then
    PREV_TAG="$(git rev-list --max-parents=0 HEAD 2>/dev/null || echo "")"
fi
{
    echo '<!DOCTYPE html>'
    echo '<html lang="zh-CN">'
    echo '<head>'
    echo '  <meta charset="UTF-8">'
    echo "  <title>TokMon v$VERSION Release Notes</title>"
    echo '  <style>'
    echo '    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #f2f2f7; background: #1c1c1e; }'
    echo '    h1 { font-size: 20px; margin-bottom: 12px; }'
    echo '    ul { line-height: 1.6; padding-left: 20px; }'
    echo '    li { margin-bottom: 6px; }'
    echo '    a { color: #0a84ff; }'
    echo '  </style>'
    echo '</head>'
    echo '<body>'
    echo "  <h1>TokMon v$VERSION</h1>"
    echo '  <ul>'
    if [[ -n "$PREV_TAG" ]]; then
        git log --pretty=format:"<li>%s</li>" "${PREV_TAG}..HEAD" 2>/dev/null || true
    else
        git log --pretty=format:"<li>%s</li>" -10 2>/dev/null || true
    fi
    echo '  </ul>'
    echo "  <p><a href=\"https://github.com/xiehuacheng/TokMon/releases/tag/v$VERSION\">查看完整 Release</a></p>"
    echo '</body>'
    echo '</html>'
} > "$RELEASE_NOTES_PATH"
echo "Generated $RELEASE_NOTES_PATH"

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
      <sparkle:releaseNotesLink>$RELEASE_NOTES_URL</sparkle:releaseNotesLink>
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
