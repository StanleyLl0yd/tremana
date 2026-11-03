# Adaptive Torrent List Refresh — M1

The TreMana macOS UI refreshes the connected Transmission RPC torrent list
automatically, using a cancellable SwiftUI task scoped to the active connection
and current scene activity. It waits once before the next request because
Connect, Start/Stop/Verify and Add Torrent already fetch immediately.

Default policy:

- **5 seconds** if any torrent is downloading or verifying (RPC status 1/2/4);
- **15 seconds** for a connected foreground window without those states;
- **30 seconds** while scene is inactive/background (subject to macOS sleep and
  process suspension; no guarantee of polling a sleeping Mac);
- **30 seconds** following a transient network error, to avoid hammering Keenetic.

The next interval is calculated after each attempt. A successful RPC refresh
updates rates, progress, status, and a last-success timestamp. The model's
\`isBusy\` guard prevents periodic polling from overlapping manual refreshes
or mutations. A cancelled task never continues after Disconnect or when the
scene state changes; the model's connection-generation guard also prevents
stale replies from restoring a disconnected session.

This updates torrent information, **not the TreMana application binary**.
Settings UI and fixed mode are a separate follow-on change.
