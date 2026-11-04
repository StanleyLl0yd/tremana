#!/usr/bin/env bash
set -euo pipefail
umask 077

app="${1:-dist/TreMana.app}"
[[ "$(uname -s)" == Darwin ]] || { echo "macOS required" >&2; exit 1; }
[[ -n "${TREMANA_CODESIGN_IDENTITY:-}" &&
   -n "${TREMANA_SIGNING_KEYCHAIN:-}" ]] ||
    { echo "Missing imported TreMana Code Signing identity" >&2; exit 1; }
[[ -d "$app" ]] || { echo "App not found: $app" >&2; exit 1; }

codesign --verify --strict --verbose=2 "$app"
original="$(codesign -dr - "$app" 2>&1 | grep '^designated => ')"
[[ -n "$original" && "$original" == *'com.sl.tremana'* ]] ||
    { echo "Unexpected bundle identifier in designated requirement" >&2; exit 1; }
[[ "$original" != *cdhash* ]] ||
    { echo "Code-hash-based identity cannot survive updates" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
ditto "$app" "$scratch/TreMana.app"
plist="$scratch/TreMana.app/Contents/Info.plist"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || exit 1
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build + 1))" "$plist"
codesign --force --sign "$TREMANA_CODESIGN_IDENTITY" \
    --keychain "$TREMANA_SIGNING_KEYCHAIN" \
    --entitlements Config/TreMana.entitlements \
    "$scratch/TreMana.app"
codesign --verify --strict "$scratch/TreMana.app"
updated="$(codesign -dr - "$scratch/TreMana.app" 2>&1 | grep '^designated => ')"
[[ "$original" == "$updated" ]] || {
    echo "Designated Requirement changed between independently signed versions" >&2
    exit 1
}
echo "TreMana signature and stable Designated Requirement verified."
