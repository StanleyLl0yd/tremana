# TreMana 0.4.0 — Zen glass layout acceptance

This design revision follows the user-approved reference, not the earlier bulky 0.3.0 file-card view. It deliberately avoids creating buttons without a distinct purpose.

## Layout
- **Top:** compact sortable/native torrent table, multiple torrents visible, configurable column widths and visibility. Initial visible columns: name (with status icon), total size, progress, download, upload, ETA, ratio, and read-only file-priority summary.
- **Bottom:** always-visible, vertically resizable detail inspector. No fullscreen/expand action. A single selected torrent has a short identifying header, tabs and compact file rows.
- **Files:** one checkbox per row to include/exclude the file from download. No duplicate right-side toggle. Priority is a separate menu; progress and size are separate read-only columns. File checkbox stays disabled for the last wanted file or while strict ordered queue controls selection. No simulated change until Transmission confirms.
- **Priority summary:** derived only from real RPC16 `fileStats`, for *every* file (including unwanted ones): all low/normal/high = that priority; different values = `Mixed`; missing/invalid metadata = em dash. The summary is **read-only** because Transmission 3.00 does not have a separate torrent-wide priority setting. It is not equivalent to the strict file queue.
- **Toolbar:** add/start/pause + search, connected profile button offering Disconnect. No second settings/appearance icon next to search. Appearance mode selection is only in app Settings.
- **Sidebar:** counts for all, active, completed and paused. A single Settings entry; numeric app version in the footer.
- **Look:** restrained native translucent materials and warm gradients, small soft corners, minimal borders, airy outer spacing, information-dense aligned rows, accessible labels. Never add decorative controls without behavior.

## Test checklist
1. Connect with saved profile and confirm the signing transition preserves Keychain access as expected.
2. In a typical 1140x740 window inspect 8+ torrents in the upper table with the details pane beneath, and drag the horizontal divider.
3. Try narrow minimum 840x560, larger windows, RU/EN localizations, dark/light appearance; no toolbar labels should overlap.
4. Confirm one functional checkbox per file and one functional priority menu; select/skip and set low/normal/high with live server readback.
5. Verify `Mixed` is shown when a torrent's file priorities differ, including a skipped file. Verify missing metadata is never silently labeled Normal.
6. Check table column customization, sorting, sidebar counts and search, connection status menu/Disconnect, and accessible Settings.
7. Check strict file queue remains independent of priority. Sequential piece mode remains correctly unavailable on Transmission 3.00/RPC16.

Hardware acceptance and full milestone repository-wide review remain separate; a green macOS CI result alone is not user approval.
