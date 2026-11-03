#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --configuration release
BIN="$(swift build --configuration release --show-bin-path)/TreMana"
APP="$ROOT/dist/TreMana.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TreMana"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
for locale_dir in "$ROOT"/Sources/TreMana/Resources/*.lproj; do
    [[ -d "$locale_dir" ]] || continue
    cp -R "$locale_dir" "$APP/Contents/Resources/"
done
codesign --force --sign - --entitlements "$ROOT/Config/TreMana.entitlements" "$APP"
codesign --verify --verbose=2 "$APP"
echo "Packaged: $APP"
