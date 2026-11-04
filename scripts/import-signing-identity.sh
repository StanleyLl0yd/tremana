#!/usr/bin/env bash
set -euo pipefail
umask 077
ulimit -c 0

[[ "$(uname -s)" == Darwin ]] || { echo "macOS runner required" >&2; exit 1; }
: "${RUNNER_TEMP:?GitHub runner temporary directory required}"
: "${GITHUB_ENV:?GitHub Actions environment file required}"
[[ -n "${TREMANA_CERT_P12_BASE64:-}" &&
   -n "${TREMANA_CERT_PASSWORD:-}" &&
   -n "${TREMANA_CERT_SHA256:-}" ]] || {
    echo "Missing protected tremana-signing environment credential or fingerprint" >&2
    exit 1
}

keychain="$RUNNER_TEMP/tremana-signing-$GITHUB_RUN_ID.keychain-db"
p12="$RUNNER_TEMP/tremana-signing-$GITHUB_RUN_ID.p12"
cert="$RUNNER_TEMP/tremana-signing-$GITHUB_RUN_ID.pem"
keychain_password="$(openssl rand -hex 24)"
printf '%s' "$TREMANA_CERT_P12_BASE64" | base64 -D > "$p12"
chmod 600 "$p12"
unset TREMANA_CERT_P12_BASE64

openssl pkcs12 -in "$p12" -passin env:TREMANA_CERT_PASSWORD \
    -nokeys -out "$cert" >/dev/null 2>&1 ||
    { echo "Invalid private signing archive or password" >&2; exit 1; }

fingerprint="$(openssl x509 -in "$cert" -noout -fingerprint -sha256 |
    awk -F= '{print $2}' | tr -d ':\r\n' | tr '[:upper:]' '[:lower:]')"
[[ "$fingerprint" == "$TREMANA_CERT_SHA256" ]] ||
    { echo "Signing identity does not match pinned SHA-256 fingerprint" >&2; exit 1; }
openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null ||
    { echo "Signing identity has expired or expires within 24 hours" >&2; exit 1; }
openssl x509 -in "$cert" -noout -text > "$RUNNER_TEMP/tremana-certificate.txt"
grep -Fq 'Code Signing' "$RUNNER_TEMP/tremana-certificate.txt" ||
    { echo "Signing identity is not a Code Signing certificate" >&2; exit 1; }
openssl x509 -in "$cert" -noout -subject |
    grep -Fq 'TreMana Code Signing' ||
    { echo "This is not the separate TreMana signing identity" >&2; exit 1; }

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain"
security import "$p12" -k "$keychain" \
    -P "$TREMANA_CERT_PASSWORD" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$cert"
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$keychain_password" "$keychain" >/dev/null
unset TREMANA_CERT_PASSWORD

identity="$(openssl x509 -in "$cert" -noout -fingerprint -sha1 |
    awk -F= '{print $2}' | tr -d ':\r\n' | tr '[:lower:]' '[:upper:]')"
[[ "$identity" =~ ^[A-F0-9]{40}$ ]] ||
    { echo "Invalid certificate SHA-1 identity selector" >&2; exit 1; }
security find-identity -v -p codesigning "$keychain" > "$RUNNER_TEMP/tremana-identities.txt"
grep -Fq "$identity" "$RUNNER_TEMP/tremana-identities.txt" ||
    { echo "Imported identity is not valid for macOS Code Signing" >&2; exit 1; }

printf 'TREMANA_CODESIGN_IDENTITY=%s\n' "$identity" >> "$GITHUB_ENV"
printf 'TREMANA_SIGNING_KEYCHAIN=%s\n' "$keychain" >> "$GITHUB_ENV"
printf 'TREMANA_SIGNING_P12=%s\n' "$p12" >> "$GITHUB_ENV"
printf 'TREMANA_SIGNING_CERT=%s\n' "$cert" >> "$GITHUB_ENV"
echo "Imported PINNED TreMana Code Signing identity into a temporary Keychain."
