# M1 — Torrent actions

TreMana exposes native multi-select actions for **Start**, **Stop** and
**Verify**. These operations are sent to the existing Transmission daemon
using the legacy RPC 16 methods \`torrent-start\`, \`torrent-stop\`, and
\`torrent-verify\`. They never change the server's global settings or stop
the daemon.

The client refuses empty, zero or negative torrent IDs. Transmission treats
missing/empty \`ids\` as ALL torrents: a malformed or empty selection must
never accidentally affect all torrents. Non-empty IDs are deduplicated and
sorted. The model also filters selections against the current torrent list.

A successful RPC action refreshes the torrent list. If the client disconnects
during a pending action or refresh, its generation guard prevents stale replies
from changing disconnected state. Verification requires UI confirmation since
it may temporarily interrupt transfers.

Actions are not yet available for \`.torrent\` files or magnets; those are
separate M1 tasks. Real-router acceptance remains necessary before claiming
the action UX is verified.
