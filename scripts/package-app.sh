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
# Build a native macOS icon from the approved TreMana remote-control artwork.
# Keep this inside the app bundle before signing so the icon is covered by the signature.
ICON_SOURCE="$ROOT/Assets/TreMana-AppIcon.webp"
ICONSET="$ROOT/dist/TreMana.iconset"
[[ -s "$ICON_SOURCE" ]] || { echo "Missing TreMana app icon source" >&2; exit 1; }
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
icon_sizes=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)
for spec in "${icon_sizes[@]}"; do
    size="${spec%%:*}"
    name="${spec#*:}"
    sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/TreMana.icns"
rm -rf "$ICONSET"
[[ -s "$APP/Contents/Resources/TreMana.icns" ]] || {
    echo "App icon was not packaged" >&2
    exit 1
}

signing_args=(--force --sign "${TREMANA_CODESIGN_IDENTITY:--}" --entitlements "$ROOT/Config/TreMana.entitlements")
if [[ -n "${TREMANA_SIGNING_KEYCHAIN:-}" ]]; then
    [[ "${TREMANA_CODESIGN_IDENTITY:--}" != "-" ]] || exit 1
    signing_args+=(--keychain "$TREMANA_SIGNING_KEYCHAIN")
fi
codesign "${signing_args[@]}" "$APP"
codesign --verify --verbose=2 "$APP"
echo "Packaged: $APP"
printf 'TreMana executable bytes: %s\n' "$(stat -f '%z' "$APP/Contents/MacOS/TreMana")"
printf 'TreMana app size (KiB): %s\n' "$(du -sk "$APP" | awk '{print $1}')"
