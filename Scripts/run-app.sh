#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The bare Command Line Tools toolchain can't find the SwiftUI macros plugin
# against newer SDKs; prefer a full Xcode install when one is present.
if ! xcode-select -p | grep -q "Xcode"; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -n1 || true)"
  if [ -n "$XCODE_APP" ]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
  fi
fi

# Desktop is iCloud-synced; the file provider stamps xattrs on build products
# that break codesign. Build in a scratch dir outside the synced tree.
SCRATCH="${TMPDIR:-/tmp}/ohmyservers-build"
swift build -c release --product OhMyServers --scratch-path "$SCRATCH"
BIN="$(swift build -c release --show-bin-path --scratch-path "$SCRATCH")/OhMyServers"
APP="$ROOT/OhMyServers.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OhMyServers"
cp "$ROOT/Sources/OhMyServers/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/OhMyServers"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Launching $APP"
open "$APP"
