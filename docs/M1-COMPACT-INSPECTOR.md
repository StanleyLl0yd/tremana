# M1 compact information layout
- Compact icon+label toolbar with macOS borderless buttons, 68 x 42 points.
- Server version (real session-get values), active and seeding counts move to the fixed-height bottom status bar.
- Main header is just title+count; static unsupported sequential-pieces warning is removed from main view, capabilities remain enforced in Core.
- Inspector expands to all available height on demand; split view minimums reduced and divider remains draggable.
- Limits tab removed at user's request; no RPC limit fields requested.
- Trackers include announce/scrape state/time/counts; peers sortable by native macOS table headers.
- Files remain read-only in this PR; separate guarded RPC mutation issue #23.

Live macOS/Keenetic acceptance is required for visual density, full-height inspector and correct RPC 16 data.