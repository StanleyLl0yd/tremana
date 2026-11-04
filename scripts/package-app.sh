#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --configuration release -Xswiftc -Osize -Xlinker -dead_strip
BIN="$(swift build --configuration release --show-bin-path)/TreMana"
APP="$ROOT/dist/TreMana.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TreMana"
printf 'TreMana executable before strip: %s bytes\n' "$(stat -f '%z' "$APP/Contents/MacOS/TreMana")"
strip -x "$APP/Contents/MacOS/TreMana"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
for locale_dir in "$ROOT"/Sources/TreMana/Resources/*.lproj; do
    [[ -d "$locale_dir" ]] || continue
    cp -R "$locale_dir" "$APP/Contents/Resources/"
done
codesign --force --sign "${TREMANA_CODESIGN_IDENTITY:--}" --entitlements "$ROOT/Config/TreMana.entitlements" "$APP"
codesign --verify --verbose=2 "$APP"
echo "Packaged: $APP"
printf 'TreMana executable bytes: %s\n' "$(stat -f '%z' "$APP/Contents/MacOS/TreMana")"
printf 'TreMana app size (KiB): %s\n' "$(du -sk "$APP" | awk '{print $1}')"
