# Remember connection — M1 UX and security acceptance

Reported on the first live M1 test: Start/Stop/Verify PASS; adding torrents
PASS; Disconnect PASS; connection profile/password persistence FAIL.

## Intended flow

1. Enter Transmission URL, username and password. Check **Remember this
   connection** before pressing **Connect** (explicit user opt-in).
2. Successful RPC authentication and torrent listing immediately connects the
   UI; then TreMana saves the profile automatically. The name is optional and
   defaults to the server hostname. There is no separate Save Profile button.
3. Non-secret metadata (profile name, RPC URL, username and HTTP opt-in) is
   stored in UserDefaults. Passwords are stored only through macOS Keychain.
4. The password text field is deliberately cleared after successful Connect.
   This is **not** loss of a securely saved password. The UI indicates when a
   previously saved password exists, without revealing it in the form.
5. On next launch, the previously used saved profile is automatically selected;
   the URL, login and HTTP opt-in reappear. Press Connect with the password
   field empty; TreMana retrieves its secret directly from Keychain.
6. The saved password cannot be reused for a different URL, username or
   HTTP opt-in configuration. Editing connection details requires credentials
   again; the former saved profile remains intact.
7. If Keychain save fails, the authenticated connection stays usable, but a
   prominent explicit error is shown in the torrent window, with macOS error
   code. No plaintext fallback is permitted.
8. Uncheck Remember connection to connect without new persistence. Use
   **Forget Selected Connection** to delete an existing profile and its Keychain
   entry.

## Live acceptance matrix

- Connect with Remember enabled, optional profile name blank: PASS only if
  connected and "Connection remembered securely" displayed.
- Disconnect, fully quit, reopen the .app: last-used endpoint, username and
  checkbox are restored without manual selection.
- Press Connect with blank password: connects successfully using Keychain.
  Blank SecureField is expected and protects the password.
- Change endpoint to an alternate test host: no saved password may be sent.
- Forget profile: profile disappears from picker and its Keychain entry is
  removed.
- Disable persistence: connect normally without a new saved profile.
- If an error occurs, copy only the message and OSStatus code, not credentials.

No claims of live Keychain acceptance until user reports these results.
