#!/bin/bash
set -euo pipefail

certificate="${TREMANA_CERT_P12_BASE64:-}"
password="${TREMANA_CERT_PASSWORD:-}"

if [[ -z "$certificate" && -z "$password" ]]; then
    echo "Signing certificate not configured: using ad-hoc signing"
    exit 0
fi
if [[ -z "$certificate" || -z "$password" ]]; then
    echo "Both signing secrets must be configured" >&2
    exit 1
fi

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

workdir="$(mktemp -d "$RUNNER_TEMP/tremana-sign.XXXXXX")"
chmod 700 "$workdir"
bundle="$workdir/identity.p12"
keychain="$workdir/identity.keychain-db"
keychain_password="$(uuidgen)"

printf '%s' "$certificate" | base64 -D > "$bundle"
chmod 600 "$bundle"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$bundle" -k "$keychain" -P "$password" -f pkcs12 -T /usr/bin/codesign
rm -f "$bundle"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
identity="$(security find-identity -p codesigning "$keychain" |
    awk '/TreMana Code Signing/ { print $2; count++ } END { if (count != 1) exit 1 }')"
[[ "$identity" =~ ^[0-9A-Fa-f]{40}$ ]] || {
    echo "Exactly one TreMana Code Signing identity is required" >&2
    exit 1
}

printf 'TREMANA_CODESIGN_IDENTITY=%s\n' "$identity" >> "$GITHUB_ENV"
printf 'TREMANA_SIGNING_KEYCHAIN=%s\n' "$keychain" >> "$GITHUB_ENV"
echo "Imported stable signing identity into the temporary runner Keychain"
