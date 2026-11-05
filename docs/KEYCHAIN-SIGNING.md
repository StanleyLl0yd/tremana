# Stable private code signing for TreMana (no paid Apple Developer)

TreMana uses its **own** long-lived self-signed certificate, separate from lueya.
Its common name is `TreMana Code Signing`. It does **not** confer Developer ID
trust or Apple notarization; Gatekeeper may require a one-time launch approval.

## One-command setup on your Mac

Requirements: macOS, `gh` (GitHub CLI authenticated with `gh auth login`),
OpenSSL, and administrator access to `StanleyLl0yd/tremana`.
Do not run this in a cloud runner or from an untrusted machine.

Download and inspect `scripts/setup-signing.sh`, then run it locally.
The script requires an interactive terminal to request your private password.

On first run it:

1. Creates a **dedicated** encrypted RSA-3072 / SHA-256 Code Signing certificate
   valid for about 10 years. It never uses or modifies the lueya identity.
2. Saves an encrypted, password-protected `.p12` and matching public `.cer`
   in `~/Library/Application Support/TreMana/signing/` with private permissions.
3. Creates the `tremana-signing` GitHub Environment with deployment branch
   restrictions **only** for `main` and `release/v*`. Existing broader
   policies are rejected; protected `main` is a prerequisite.
4. Uploads environment-scoped **secrets** `TREMANA_CERT_P12_BASE64`,
   `TREMANA_CERT_PASSWORD`, and pinned public environment **variable**
   `TREMANA_CERT_SHA256`. Values are passed through stdin and are never written
   to git, terminal output, GitHub logs or public artifacts.
5. **Does not run a release or change a published Git tag.**

On subsequent runs it reuses the SAME `.p12` and certificate and checks the
saved public certificate and GitHub's pinned fingerprint. A wrong password or
missing half of an existing identity causes a hard error. It cannot rotate
keys silently.

If GitHub contains an **old pinned fingerprint** but neither signing secret
was uploaded (for example, from an interrupted prior setup), the script displays
both public fingerprints and asks you to type `REBIND` before replacing this
orphaned public pin. It never generates a second key during this recovery. If
GitHub already has signing secrets from a different identity, it **refuses
replacement**: find the previous encrypted `.p12` or investigate the mismatch.
There is no unattended reset and no option to override this restriction.

If setup stopped after creating the certificate, rerun the newer pinned
`setup-signing.sh` file. When asked for the *existing* password, use the one
chosen on the first run; do not delete `TreMana-Code-Signing.p12` or `.cer`.

The script is based on the **corrected** lueya setup and specifically avoids
the unsupported `openssl x509 -ext` parameter from the original script:
the Code Signing EKU is verified using `openssl x509 -noout -text` in a file,
then `grep` (also avoiding SIGPIPE from `grep -q` in a pipe).

### Keep your identity safe

Back up the encrypted `.p12` file and password **separately** in protected
storage. Losing them requires new identity migration, potentially causing macOS
to ask for Keychain permissions again. Never share either with a support agent,
post in chat, attach to issues, or put into version control.

The `.p12` uses 3DES/SHA-1 for legacy PKCS#12 envelope compatibility with
Apple Security.framework; the X.509 signing certificate itself uses SHA-256.
Protect the archive with a strong unique password (at least 24 bytes).

## GitHub pipelines

- Regular pull-request CI stays **ad-hoc signed**, with no signing secrets.
- `release.yml` on protected `main` and `preview-release.yml` on numerical
  `release/vX.Y.Z` branches require `environment: tremana-signing`.
- The job accepts only the repository owner as workflow actor and triggering
  actor. The environment allows only `main` and `release/v*` branches.
  **Protect release branches with rulesets if you grant collaborators write
  access; environment branch-name restrictions alone do not protect code
  on an unprotected branch.**
- The identity is imported into a temporary macOS runner Keychain and
  validated against the SHA-256 fingerprint, expiry and Code Signing EKU.
  The runner does not modify macOS user/system certificate trust settings:
  adding a trusted root can require interactive authorization and hang CI.
  Keychain commands have bounded timeouts; signing and the stable designated
  requirement are validated separately.
  Signing fails closed if secrets are absent or inconsistent.
- `scripts/verify-signing-identity.sh` verifies the actual app signature and
  its Designated Requirement. It independently re-signs a copy with a changed
  build number and requires the Designated Requirement to remain identical.
- The temporary Keychain and certificate files are destroyed after each job.
  The ZIP must be downloaded back from GitHub and byte-compared after release.

The first change from an ad-hoc signature to the stable certificate may still
cause a single Keychain authorization prompt. Since 0.4.2, saving or replacing
a password also sets a macOS file-based Keychain ACL explicitly restricted to
the currently signed TreMana app (using its designated requirement), instead
of inheriting a legacy ad-hoc app identity. This does **not** silently erase or
weaken ACLs on existing credentials. A pre-existing item may still require the
user to select **Always Allow** once and enter the login Keychain password,
or to re-enter the server password to update its ACL. **Do not** recommend
"Allow all applications to access this item": it expands access to secrets.

Test *two consecutive signed versions* with the same stored password; a single
build cannot prove update persistence. A recurring prompt after **Always Allow**
must be diagnosed on the actual Mac (Keychain item Access Control, signed app
designated requirement, Keychain lock state) and must not be reported as fixed
by unit tests alone. Keep bundle identifier `com.sl.tremana` and Keychain
service/account identifiers unchanged across all versions.

## After local setup

Confirm the script reports the environment secrets and fingerprint variable.
Inform the project maintainer that **setup completed**; do not share the
password, certificate, or base64 content. The prepared `0.3.0` release workflow
can then be rerun. Release creation remains a separate operation.

References:
- https://docs.github.com/actions/reference/workflows-and-actions/deployments-and-environments
- https://developer.apple.com/library/archive/technotes/tn2206/
- https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

## Deferred Keychain reads (0.4.3)

Opening a remembered connection or selecting a profile reads only nonsecret
metadata and does **not** query the Keychain password. The first password read
happens on explicit Connect, and only for an unchanged matching endpoint.
The same app signature, item service/account identifiers and restricted ACLs
are retained. macOS can still request one-time permission after an app update;
choose **Always Allow** only for the expected signed TreMana. Never grant all
apps access to the secret.

The mock-store regression test counts password reads, requiring zero during
profile display/selection and a read only after Connect. CI cannot verify
cross-version Keychain behavior on the user's actual Mac; signed update and
relaunch tests remain mandatory.
