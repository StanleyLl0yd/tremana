# M1 — Safe server-side Move and Rename (draft)

TreMana uses Transmission 3.00 / RPC 16 operations on the **Keenetic server**,
not local Finder operations. This feature is held in draft until device acceptance.

## Actions

- **Move server data:** one positive explicit torrent ID, canonical absolute
  server directory and `torrent-set-location` with `move=true`. No silent
  `move=false` reattach/search operation. Destination must differ from the
  current download directory. No implicit folder creation, privilege escalation,
  fallback to local filesystem, or batch operation.
- **Rename server file/folder:** one positive explicit torrent ID;
  `torrent-rename-path` with an existing relative path derived from the
  torrent's current file list and a validated single new component. Rename is
  not an arbitrary display-name edit. Candidate paths include ancestor folders.
- **Confirmation:** explicit dialog after entering a target, with warnings
  about remote disk effects, permissions and time. Re-fetch live torrent details
  just before mutation and reject reused IDs when info-hash differs, changed
  download directories, or modified file lists. Refresh and confirm the result.
- **Input safety:** reject root destination, relative move destinations,
  `..`/`.` traversal, duplicate delimiters, NUL/control characters,
  backslashes and surrounding whitespace. Preserve Unicode valid names.
- **Connectivity:** if the connection changes while awaiting a response,
  discard its UI result. An already-sent remote operation may still complete;
  never imply client-side cancellation reverts a server move.

## Real Keenetic acceptance (disposable torrent and data only)

- [ ] Move a stopped disposable multi-file torrent to an existing writable
      absolute destination; verify path and files via Transmission/server.
- [ ] Repeat with active transfer; verify progress/behavior after moving.
- [ ] Rename one file and a common parent folder; confirm file lists and hashes.
- [ ] Verify path with spaces/Unicode and safe nested folders.
- [ ] Reject root, traversal, Windows/SMB paths and invalid names without RPC.
- [ ] Reject changed torrent ID/hash, path or file list since sheet opened.
- [ ] Test permission denied, no space, pre-existing destination and disconnect
      during in-flight request; inspect results in Transmission.
- [ ] Verify VoiceOver, focus/escape and EN/RU native strings.

No production release or M1 closure before this acceptance and the full
repository-wide security/code review gate in AGENTS.md.
