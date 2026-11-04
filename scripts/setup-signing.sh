#!/usr/bin/env bash
set -euo pipefail
umask 077
ulimit -c 0

# Create once, reuse forever. Do not rotate a private key on repeated setup.
REPO="StanleyLl0yd/tremana"
ENVIRONMENT="tremana-signing"
IDENTITY_NAME="TreMana Code Signing"
OUTPUT_DIR="$HOME/Library/Application Support/TreMana/signing"
P12="$OUTPUT_DIR/TreMana-Code-Signing.p12"
CERT="$OUTPUT_DIR/TreMana-Code-Signing.cer"
API="repos/$REPO/environments/$ENVIRONMENT"
POLICIES="$API/deployment-branch-policies"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail "Requires macOS."
for command_name in gh openssl base64 awk grep cmp tr wc mktemp; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Missing $command_name"
done
[[ -r /dev/tty ]] || fail "Interactive terminal required."
gh auth status -h github.com >/dev/null 2>&1 ||
    fail "Authenticate GitHub CLI: gh auth login"
[[ "$(gh repo view "$REPO" --json nameWithOwner --jq '.nameWithOwner')" == "$REPO" ]] ||
    fail "Cannot access the TreMana repository."
[[ "$(gh api "repos/$REPO/branches/main" --jq '.protected')" == true ]] ||
    fail "Protected main is required. Check GitHub branch protection."

[[ ! -L "$OUTPUT_DIR" && ! -L "$P12" && ! -L "$CERT" ]] ||
    fail "Symlink in signing identity path is not allowed."
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
[[ ! -L "$OUTPUT_DIR" && ! -L "$P12" && ! -L "$CERT" ]] ||
    fail "Symlink in signing identity path is not allowed."

tmp="$(mktemp -d)"
cleanup() {
    unset TREMANA_SIGNING_PASS confirm
    rm -rf "$tmp"
}
trap cleanup EXIT

if [[ -f "$P12" || -f "$CERT" ]]; then
    [[ -f "$P12" && -f "$CERT" ]] ||
        fail "Partial identity found. Restore both files; refusing key rotation."
    echo "Existing TreMana identity found. Reusing it; NOT rotating the private key."
    read -r -s -p "Existing .p12 password: " TREMANA_SIGNING_PASS </dev/tty
    printf '\n'
else
    echo "Creating a dedicated 10-year RSA-3072/SHA-256 TreMana Code Signing identity."
    echo "Use a unique password of at least 24 bytes and store it in your password manager."
    read -r -s -p "New .p12 password: " TREMANA_SIGNING_PASS </dev/tty
    printf '\n'
    [[ "$(printf '%s' "$TREMANA_SIGNING_PASS" | wc -c | tr -d ' ')" -ge 24 ]] ||
        fail "Password must contain at least 24 bytes."
    read -r -s -p "Repeat .p12 password: " confirm </dev/tty
    printf '\n'
    [[ "$TREMANA_SIGNING_PASS" == "$confirm" ]] ||
        fail "Passwords do not match."
    unset confirm

    cat > "$tmp/codesign.cnf" <<'OPENSSL_CONFIG'
[ req ]
prompt = no
distinguished_name = identity
x509_extensions = codesign
[ identity ]
CN = TreMana Code Signing
O = TreMana Personal Development
[ codesign ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
OPENSSL_CONFIG

    export TREMANA_SIGNING_PASS
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
        -aes-256-cbc -pass env:TREMANA_SIGNING_PASS \
        -out "$tmp/key.pem" >/dev/null 2>&1 ||
        fail "Private key generation failed."
    openssl req -new -x509 -sha256 -days 3650 \
        -key "$tmp/key.pem" -passin env:TREMANA_SIGNING_PASS \
        -config "$tmp/codesign.cnf" -extensions codesign \
        -out "$tmp/cert.pem" ||
        fail "Certificate creation failed."
    openssl x509 -in "$tmp/cert.pem" -outform DER -out "$tmp/cert.cer"
    # Compatibility PKCS#12 ciphers for Apple Security.framework import.
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -name "$IDENTITY_NAME" \
        -passin env:TREMANA_SIGNING_PASS -passout env:TREMANA_SIGNING_PASS \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
        -out "$tmp/identity.p12" ||
        fail "Encrypted PKCS#12 export failed."
    [[ ! -e "$P12" && ! -e "$CERT" ]] ||
        fail "Identity files appeared while generating. Refusing overwrite."
    mv "$tmp/identity.p12" "$P12"
    mv "$tmp/cert.cer" "$CERT"
    chmod 600 "$P12" "$CERT"
    echo "Created dedicated signing identity."
fi

[[ -f "$P12" && -f "$CERT" ]] || fail "Both .p12 and .cer are required."
[[ ! -L "$P12" && ! -L "$CERT" ]] || fail "Symlink identity is forbidden."
export TREMANA_SIGNING_PASS
openssl pkcs12 -in "$P12" -passin env:TREMANA_SIGNING_PASS \
    -nokeys -out "$tmp/extracted.pem" >/dev/null 2>&1 ||
    fail "Wrong password or invalid .p12."
openssl x509 -in "$tmp/extracted.pem" -noout -text > "$tmp/certificate.txt"
grep -Fq 'Code Signing' "$tmp/certificate.txt" ||
    fail "Code Signing extended key usage is missing."
openssl x509 -in "$tmp/extracted.pem" -noout -subject |
    grep -Fq "$IDENTITY_NAME" ||
    fail "Unexpected certificate identity. The lueya key must NOT be reused."
openssl x509 -in "$tmp/extracted.pem" -noout -checkend 604800 >/dev/null ||
    fail "Signing certificate expires within seven days."
openssl x509 -in "$tmp/extracted.pem" -outform DER -out "$tmp/extracted.cer"
cmp -s "$tmp/extracted.cer" "$CERT" ||
    fail "Certificate does not match saved identity; refusing silent rotation."

fingerprint="$(openssl x509 -in "$tmp/extracted.pem" -noout -fingerprint -sha256 |
    awk -F= '{print $2}' | tr -d ':\r\n' | tr '[:upper:]' '[:lower:]')"
[[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] ||
    fail "Unexpected fingerprint format."
printf 'TreMana certificate SHA-256: %s\n' "$fingerprint"
openssl x509 -in "$tmp/extracted.pem" -noout -subject -dates

# The protected signing environment accepts ONLY main and release/v* branches.
if gh api "$API" >/dev/null 2>&1; then
    mode="$(gh api "$API" --jq 'if .deployment_branch_policy == null then "unrestricted" elif .deployment_branch_policy.custom_branch_policies == true then "selected" else "incompatible" end')"
    case "$mode" in
        selected) ;;
        unrestricted)
            # GitHub may auto-create an unrestricted environment on first CI run.
            # Restrict it BEFORE uploading any certificate secrets.
            printf '%s' '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
                gh api --method PUT "$API" --input - >/dev/null ||
                fail "Unable to restrict the existing signing environment."
            echo "Restricted previously unconfigured GitHub Environment."
            ;;
        *) fail "Existing environment has incompatible branch restrictions; fix manually." ;;
    esac
else
    printf '%s' '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' |
        gh api --method PUT "$API" --input - >/dev/null ||
        fail "Unable to create the protected signing environment."
    echo "Created GitHub Environment: $ENVIRONMENT"
fi

policy_names="$(gh api "$POLICIES?per_page=100" --jq '.branch_policies[].name')" ||
    fail "Unable to read deployment branch policies."
while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == main || "$pattern" == 'release/v*' ]] ||
        fail "Environment contains unexpected allowed branch: $pattern"
done <<< "$policy_names"
for pattern in main 'release/v*'; do
    if ! grep -Fxq -- "$pattern" <<< "$policy_names"; then
        gh api --method POST "$POLICIES" -f "name=$pattern" -f type=branch >/dev/null ||
            fail "Cannot restrict environment to $pattern"
        echo "Added environment branch policy: $pattern"
    fi
done

pinned="$(gh api "$API/variables/TREMANA_CERT_SHA256" --jq .value 2>/dev/null || true)"
[[ -z "$pinned" || "$pinned" == "$fingerprint" ]] ||
    fail "GitHub environment already pins a DIFFERENT certificate. Refusing rotation."

base64 < "$P12" | tr -d '\r\n' |
    gh secret set TREMANA_CERT_P12_BASE64 --repo "$REPO" --env "$ENVIRONMENT" ||
    fail "Failed to upload the certificate secret."
printf '%s' "$TREMANA_SIGNING_PASS" |
    gh secret set TREMANA_CERT_PASSWORD --repo "$REPO" --env "$ENVIRONMENT" ||
    fail "Failed to upload the certificate password secret."
printf '%s' "$fingerprint" |
    gh variable set TREMANA_CERT_SHA256 --repo "$REPO" --env "$ENVIRONMENT" ||
    fail "Failed to pin certificate fingerprint."
unset TREMANA_SIGNING_PASS

echo "TreMana identity uploaded to GitHub Environment '$ENVIRONMENT'."
gh secret list --repo "$REPO" --env "$ENVIRONMENT"
gh variable list --repo "$REPO" --env "$ENVIRONMENT"
echo "Keep an encrypted private backup of the .p12 and its password."
echo "No release was triggered. Do not send private key material to anyone."
