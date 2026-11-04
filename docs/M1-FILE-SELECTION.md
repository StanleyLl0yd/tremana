# M1 — File selection (Transmission 3.00 / RPC 16)

## Implementation

The Files inspector exposes a native checkbox for each file when a single
torrent is selected and Transmission reports matching `files` and `fileStats`
arrays. A checkbox controls whether Transmission should download that file;
it does not delete completed data, and it does not control piece order.

Every edit:

1. Checks the displayed torrent ID, file index and current wanted state.
2. Fetches fresh file metadata from that exact torrent to detect external edits.
3. Refuses to exclude the final wanted file.
4. Calls `torrent-set` with `ids: [torrentID]` and exactly one 0-based index
   under either `files-wanted` or `files-unwanted`.
5. Does not use file priorities. It does not send empty index arrays.
6. Reloads that torrent's detail after RPC success; checkboxes do not
   optimistically change on a failed operation.
7. Suppresses competing automatic detail reads during the mutation and
   discards stale responses after selection changes/disconnects.

Missing/inconsistent `fileStats` disables editing, rather than guessing.
A selected file may still share pieces with another file at its boundaries.
This feature is **not** strict sequential file queueing (M2).

## Manual acceptance on real macOS 27 / Keenetic

Use only a disposable multi-file test torrent; never test against valuable data.

- [ ] Toggle a middle file off and back on; confirm Transmission's own
      file selection agrees with the checkbox.
- [ ] Attempt to uncheck the final wanted file; verify it remains selected
      without a destructive daemon request.
- [ ] Edit file selection in another Transmission client before clicking;
      verify stale intent is rejected and refreshed.
- [ ] Disconnect or switch torrent while a mutation is pending; ensure old
      file state never appears under the new torrent.
- [ ] Confirm there is no file deletion and no unexpected file-priority change.
- [ ] Confirm VoiceOver labels, compact layout and both EN/RU translations.

GitHub CI covers exact RPC payloads, invalid indices, last-file refusal,
stale server changes and error handling. Passing CI alone does not count as
real-device acceptance.
