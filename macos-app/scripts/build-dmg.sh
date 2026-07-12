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
RELEASE_NOTES_MD_SOURCE="$APP_ROOT/release-notes.md"

# Convert the Chinese Markdown release notes into a simple HTML page for Sparkle.
if [[ -f "$RELEASE_NOTES_MD_SOURCE" ]]; then
    python3 - "$RELEASE_NOTES_MD_SOURCE" "$RELEASE_NOTES_PATH" "$VERSION" <<'PY'
import html, re, sys
md_path, out_path, version = sys.argv[1:4]
with open(md_path, encoding='utf-8') as f:
    lines = f.read().splitlines()

def inline(s):
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'\*([^*]+)\*', r'<em>\1</em>', s)
    s = re.sub(r'`([^`]+)`', r'<code>\1</code>', s)
    return s

out = [
    '<!DOCTYPE html>',
    '<html lang="zh-CN">',
    '<head>',
    '  <meta charset="UTF-8">',
    f'  <title>TokMon v{version} 更新日志</title>',
    '  <style>',
    '    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #f2f2f7; background: #1c1c1e; }',
    '    h1 { font-size: 20px; margin-bottom: 12px; }',
    '    h2 { font-size: 16px; margin-top: 20px; margin-bottom: 8px; color: #e5e5ea; }',
    '    ul { line-height: 1.6; padding-left: 20px; }',
    '    li { margin-bottom: 6px; }',
    '    p { line-height: 1.5; margin: 8px 0; }',
    '    code { font-family: Menlo, monospace; background: #2c2c2e; padding: 2px 5px; border-radius: 4px; }',
    '    pre { background: #2c2c2e; padding: 10px; border-radius: 8px; overflow-x: auto; }',
    '    a { color: #0a84ff; }',
    '  </style>',
    '</head>',
    '<body>',
    f'  <h1>TokMon v{version} 更新日志</h1>',
]

in_list = False
in_code = False
code_lines = []

def flush_code():
    global in_code, code_lines
    if code_lines:
        out.append('  <pre><code>' + html.escape('\n'.join(code_lines)) + '</code></pre>')
    in_code = False
    code_lines = []

for raw in lines:
    line = raw.rstrip()
    if line.startswith('```'):
        if in_list:
            out.append('  </ul>')
            in_list = False
        if in_code:
            flush_code()
        else:
            in_code = True
        continue
    if in_code:
        code_lines.append(line)
        continue
    if not line:
        if in_list:
            out.append('  </ul>')
            in_list = False
        continue
    if line.startswith('## '):
        if in_list:
            out.append('  </ul>')
            in_list = False
        out.append(f'  <h2>{inline(line[3:])}</h2>')
    elif line.startswith('- '):
        if not in_list:
            out.append('  <ul>')
            in_list = True
        out.append(f'    <li>{inline(line[2:])}</li>')
    else:
        if in_list:
            out.append('  </ul>')
            in_list = False
        out.append(f'  <p>{inline(line)}</p>')

if in_list:
    out.append('  </ul>')
flush_code()
out.extend([
    f'  <p><a href="https://github.com/xiehuacheng/TokMon/releases/tag/v{version}">查看完整 Release</a></p>',
    '</body>',
    '</html>',
])

with open(out_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out))
PY
    echo "Generated $RELEASE_NOTES_PATH from $RELEASE_NOTES_MD_SOURCE"
else
    echo "Warning: $RELEASE_NOTES_MD_SOURCE not found. Falling back to a minimal Chinese release notes page." >&2
    cat > "$RELEASE_NOTES_PATH" <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>TokMon v$VERSION 更新日志</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #f2f2f7; background: #1c1c1e; }
    h1 { font-size: 20px; margin-bottom: 12px; }
    p { line-height: 1.5; }
    a { color: #0a84ff; }
  </style>
</head>
<body>
  <h1>TokMon v$VERSION 更新日志</h1>
  <p>详情请前往 <a href="https://github.com/xiehuacheng/TokMon/releases/tag/v$VERSION">GitHub Release 页面</a> 查看。</p>
</body>
</html>
EOF
    echo "Generated fallback $RELEASE_NOTES_PATH"
fi

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
