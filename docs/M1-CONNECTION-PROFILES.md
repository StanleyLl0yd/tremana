# M1 — Connection profiles and Keychain

Connection profile metadata (display name, RPC URL, username and explicitly
chosen HTTP allowance) is stored in UserDefaults as JSON. Passwords are never
included in that JSON, GitHub, logs or diagnostics.

Only after the user chooses "Remember password in Keychain" and saves a profile,
the password is written as a macOS generic password via SecItemUpdate/SecItemAdd.
The Keychain entry is indexed by a random profile UUID and TreMana-specific
service name. Deleting a profile removes the matching Keychain entry. If
"Remember password" is disabled, saving deletes an older stored password.

The Keychain operations execute inside an actor rather than blocking the
macOS UI. Profile selection does not expose the saved secret in the password
field. During connection, TreMana retrieves it only when the stored RPC URL,
username and HTTP allowance all still match the current connection fields;
editing the endpoint prevents automatic reuse of the secret with a new host.

Profile updates preserving a stored password are forbidden when the
authentication endpoint changes. This is enforced by both the model and
the persistence layer. Incorrect/missing Keychain entitlements or an inaccessible
login keychain are surfaced as errors, never bypassed.

The Keychain implementation uses the standard macOS SecItem API and defaults
to the process keychain. The ad-hoc signed CI app is not a notarized release;
real Mac acceptance should include password save, application restart, profile
select, connect, editing the URL to confirm the saved secret is not reused,
and deletion.
