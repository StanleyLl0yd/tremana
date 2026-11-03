# M1 — Native torrent inspector, Transmission 3.00 (RPC 16)

Selecting **one** torrent opens its lower inspector. The native macOS
\`VSplitView\` divider is resizable and keeps the list above a separate
details pane. Selecting no rows or multiple rows displays an explicit
empty state; no broad request is sent to the server.

The inspector supports six read-only tabs:
- **Details:** downloaded/uploaded bytes, speeds, ETA, ratio, peer counts,
  total and selected sizes, remote save directory, hash, creator, dates,
  comment and Transmission error.
- **Files:** file paths, length, completed bytes, per-file progress and
  wanted/skipped flag reported by RPC. This view does not change selection,
  file priorities or strict queue state.
- **Trackers:** tracker stats when available, otherwise tracker URLs.
- **Peers:** peer address, client name, progress and both transfer rates.
- **Web Seeds:** server-reported webseed URLs, rendered as plain text.
- **Limits:** reported per-torrent rate limits and inheritance, read-only
  pending dedicated editing controls.

All data is requested using \`torrent-get\` with the **single explicit positive
torrent ID** and fields supported by RPC 16. No \`ids: []\`, missing IDs, or
all-torrent detail query is used. Optional fields tolerate magnet metadata
not yet available. Data refreshes every 15 seconds while selected; user
mutations refresh selection details immediately. Disconnect and rapid row
changes discard stale requests using connection/selection generations.

Current UI is intentionally English to match the existing application;
localization remains a separate milestone. The inspector is not an embedded
torrent engine and does not imply that unsupported server functions exist.
Manual testing on real Keenetic is necessary for Files/Trackers/Peers data.
