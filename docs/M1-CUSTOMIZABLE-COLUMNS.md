# M1 customizable native torrent columns

The main torrent list uses native SwiftUI TableColumnCustomization and
TableColumnForEach (macOS 27). Right-click a column header to show or
hide columns. Drag headers to reorder. The per-window layout persists
with SceneStorage. User-resized widths are stored separately for the torrent list
and file inspector, keyed by stable column identifiers; they survive app restarts
without replacing the existing visibility/order customization state.

Visible by default: Name, Progress, Status, Download, Upload, Seeds,
Leeches, ETA, Ratio. Optional: Added, Total Size, Downloaded, Uploaded,
Remaining, Connected Peers, Queue Position.

The main 5/15/30-second polling requests only scalar Torrent RPC16 fields.
Tracker swarm counts use an additional separate torrent-get request for
id and trackerStats every 60 seconds while connected and auto-refresh enabled.
Each swarm number is the maximum reported by one tracker, not a sum; the
same remote peers may appear on several trackers. Missing/unknown counts
are displayed as an em dash, never misrepresented as zero.

No credentials or user file contents are stored in the column settings.
