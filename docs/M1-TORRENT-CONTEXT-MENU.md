# Torrent right-click menu (M1)

Context actions use the actual clicked Table row selection, not a global
all-torrents shortcut. Both Core and RPC transport validate positive explicit
torrent IDs, and reject missing or empty IDs because Transmission RPC16
otherwise treats those as all torrents.

Available on right-click: Start, Start Now (bypass queue), Pause (RPC stop),
Verify Downloaded Data with explanation, Reannounce to Trackers, Copy Magnet
Link (one torrent), Remove Torrent with a separate choice to keep or delete
server files. Both removal paths require explicit confirmation; deletion is
destructive on the remote Keenetic. No local Finder Open, category/labels,
or unverified server-path operations are shown.

Verify compares local data against piece hashes; it is not antivirus.
The main toolbar retains Add, Start, Pause, Disconnect. Manual Refresh is
available from the Torrents app menu with Cmd+R. Automatic updates continue
according to the configured policy.

Move and Rename are deferred for dedicated server-path safeguards. Files
wanted/unwanted editing is tracked in issue #23. Real device acceptance remains
required for context menu, clipboard and destructive confirmation.
