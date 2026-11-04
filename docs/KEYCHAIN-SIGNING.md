# Stable code signing without paid Apple Developer

## Why Keychain prompts reappear

The current release script signs with `codesign --sign -` (ad-hoc). Its code identity is not stable across builds, so macOS may ask for Keychain access after every update. A long-lived self-signed **Code Signing** identity is suitable for private testing: it gives future versions a consistent *designated requirement*. This is not Apple Developer ID or notarization and does not bypass Gatekeeper.

## Create your certificate once

1. On your Mac open **Keychain Access**.
2. Use **Keychain Access → Certificate Assistant → Create a Certificate**.
3. Set name **TreMana Code Signing**, Identity Type **Self Signed Root**, Certificate Type **Code Signing**.
4. Choose **Let me override defaults**. Set a sensible lifetime and secure RSA key (3072 or 4096 bits if offered); preserve Code Signing key usage. Complete the assistant.
5. Under **login → My Certificates** confirm the certificate has a matching **private key**.
6. Keep the certificate/private key pair permanently, ideally backed up securely. Do not recreate it per version.

Apple: https://support.apple.com/guide/keychain-access/kyca8916/mac

## Export for trusted GitHub release builds

1. In Keychain Access select the **certificate together with its private key** and choose **File → Export Items…**.
2. Export an encrypted `.p12` PKCS#12 bundle, with a strong, unique export password.
3. Keep the `.p12` in a private folder outside Git repositories and make a secure backup.
4. To convert it to a GitHub encrypted secret value on macOS, use:

   ```bash
   base64 -i "$HOME/private/TreMana-Code-Signing.p12" | tr -d '\n' | pbcopy
   ```

5. In your repository **Settings → Secrets and variables → Actions**, create `TREMANA_CERT_P12_BASE64` (paste clipboard) and `TREMANA_CERT_PASSWORD` (the export password). Never post these values to ChatGPT or any issue, log, artifact, or commit.
6. Clear the clipboard. Prefer restricted release environments if multiple collaborators have write access.

A workflow must import this identity into a temporary runner Keychain and sign the application with it. Until this setup is complete, the existing release workflow uses ad-hoc signing. Publishing a release with a generated, disposable certificate would **not** solve the issue.

## Check two consecutive versions

```bash
codesign --verify --strict --verbose=2 /Applications/TreMana.app
codesign -d -r- /Applications/TreMana.app 2>&1
codesign -dv /Applications/TreMana.app 2>&1
security find-identity -v -p codesigning
```

The signing identity and designated requirement must remain stable between releases; test opening the same saved Transmission profile across an upgrade. The first move from ad-hoc to certificate signing may prompt again once. Never disable Gatekeeper globally or grant Keychain access to all applications.

Apple signing background: https://developer.apple.com/library/archive/technotes/tn2206/
