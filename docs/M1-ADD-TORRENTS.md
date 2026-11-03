# M1 — Add torrents via Transmission RPC 16

TreMana supports adding v1 magnet links and user-selected \`.torrent\` files.
Both use the existing daemon's legacy \`torrent-add\` RPC method.

- Magnet: \`filename\` carries a validated \`magnet:?xt=urn:btih:...\` link.
- File: \`metainfo\` carries base64-encoded file bytes; no local Mac path is
  sent to Transmission. Files are selected with the sandboxed macOS file
  importer and granted read-only user-selected file access.
- The \`paused\` flag is explicit; users can choose whether to start at once.
- The client distinguishes \`torrent-added\` from \`torrent-duplicate\` and
  reports the result clearly.
- Empty/oversized metainfo, non-magnet URLs and invalid info hashes are
  rejected *before* contacting Transmission.
- The connection-generation guard prevents stale post-disconnect replies
  from changing the current UI state.

This feature does not implement BitTorrent networking, download modes, labels,
or category management. A real Keenetic manual acceptance test is still
required to validate the native file picker and RPC mutator behavior.
