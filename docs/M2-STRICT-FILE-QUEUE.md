# M2 — Strict file ordering: acceptance and limitations

## Scope

- Per-torrent **Download files in order…** operates using explicit Transmission 3.00/RPC16 `files-wanted` and `files-unwanted` fields. It is **not** a change to high/normal/low priorities.
- Files are processed in the original torrent metadata order (ascending file index) among the files previously selected for download.
- Only the current incomplete file remains wanted. After it is complete, TreMana selects the next incomplete file. After all selected files complete it restores the original wanted selection.
- The queue is persisted and rechecked against the torrent info hash, file paths and lengths, and actual wanted masks. On mismatch it pauses without overriding third-party edits.
- **Requires TreMana running and connected to advance.** When macOS sleeps, TreMana quits or the network is unavailable, the current file can finish but the next file waits. A 12-second foreground/background refresh task attempts advancement whenever the app is active.
- BitTorrent piece boundaries may overlap adjacent files. That does not imply strict piece-order downloading.
- The other independent setting, **Download pieces in order…**, remains unsupported on Keenetic Transmission 3.00/RPC16. Its menu opens a capability explanation instead of performing a fake operation.

## Hardware test (disposable torrent only)

1. Connect to a test Transmission 3.00 / RPC16 server on Keenetic.
2. Use a multifile disposable torrent with at least three files. In the inspector **Files**, uncheck one file while at least one other wanted file remains. Confirm with another client and refresh.
3. Change Low / Normal / High priority for a wanted file; verify the priority round trips after a full reload, and that the wanted mask does not change.
4. Right-click torrent → **Download files in order…** and confirm. In the Files inspector, verify one incomplete file is selected, the ordered mode indicator appears, and manual wanted toggles are disabled during queue control.
5. Allow the first file to finish; confirm next file is enabled while all others are unwanted. Repeat for the next file; confirm the last stage restores the original wanted selection.
6. In a separate test, quit TreMana while one file is downloading. On reopening verify the queue resumes safely without deleting or redownloading files, and advances only when the current file completes.
7. Change file selection in a separate Transmission client during the queue. TreMana must refuse to overwrite the drift and explain why.
8. Disable ordered downloading; verify the original wanted set returns. No file should be removed from server storage.
9. Right-click → **Download pieces in order…**: verify a clear unsupported-capability notice appears and no download setting is modified.
10. Test RU and EN, minimum 840-point window, light/dark appearance, three toolbar presentation modes, and that Disconnect is easy to locate on the left.

## Release gate

- Exact-head macOS 27 Swift test and package CI must succeed.
- Manual macOS + Keenetic tests above are not yet signed off.
- M1 and M2 final acceptance require complete repository-wide audit/security review and test evidence.
- Self-signed certificate optional mechanism is prepared but cannot be verified without owner-provided encrypted GitHub Secrets; until then release signing remains ad-hoc.
