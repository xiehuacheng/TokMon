#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$APP_ROOT/.." && pwd)"
APP_NAME="AgentMon"
RELEASE_DIR="$APP_ROOT/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
SERVER_DIR="$RESOURCES_DIR/AgentMonServer"

find_node_runtime() {
  if [[ -n "${AGENTMON_NODE_RUNTIME:-}" ]]; then
    printf '%s\n' "$AGENTMON_NODE_RUNTIME"
    return
  fi

  {
    find "$HOME/.nvm/versions/node" -path '*/bin/node' -type f 2>/dev/null || true
    command -v node || true
    printf '%s\n' /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node
  } | awk 'NF && !seen[$0]++' | while IFS= read -r candidate; do
    [[ -x "$candidate" ]] || continue
    "$candidate" -e "const Database = require('better-sqlite3'); const db = new Database(':memory:'); db.close();" >/dev/null 2>&1 || continue
    if otool -L "$candidate" | grep -q 'libnode'; then
      continue
    fi
    printf '%s\n' "$candidate"
    return
  done
}

NODE_SOURCE="$(find_node_runtime)"
if [[ -z "$NODE_SOURCE" ]]; then
  echo "Unable to find a portable Node runtime that can load better-sqlite3." >&2
  echo "Set AGENTMON_NODE_RUNTIME=/path/to/node and retry." >&2
  exit 1
fi

cd "$APP_ROOT"
swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$RESOURCES_DIR"

cp "$APP_ROOT/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$APP_ROOT/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_ROOT/Assets/AgentMon.icns" "$RESOURCES_DIR/AgentMon.icns"

mkdir -p "$SERVER_DIR"
cp "$REPO_ROOT/package.json" "$SERVER_DIR/package.json"
cp "$REPO_ROOT/package-lock.json" "$SERVER_DIR/package-lock.json"
cp "$REPO_ROOT/tsconfig.json" "$SERVER_DIR/tsconfig.json"
cp -R "$REPO_ROOT/src" "$SERVER_DIR/src"
cp -R "$REPO_ROOT/public" "$SERVER_DIR/public"
cp -R "$REPO_ROOT/node_modules" "$SERVER_DIR/node_modules"

mkdir -p "$RESOURCES_DIR/Node/bin"
cp "$NODE_SOURCE" "$RESOURCES_DIR/Node/bin/node"
chmod +x "$RESOURCES_DIR/Node/bin/node"

printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Built $APP_BUNDLE"
