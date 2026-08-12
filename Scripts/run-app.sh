#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product OhMyServers
BIN="$(swift build -c release --show-bin-path)/OhMyServers"
APP="$ROOT/OhMyServers.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OhMyServers"
cp "$ROOT/Sources/OhMyServers/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/OhMyServers"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Launching $APP"
open "$APP"
