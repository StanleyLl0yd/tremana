# M1 connection and command bar UX acceptance (v0.2.1)

## Before connecting
- The connection form has one visible, prominent **Connect** button next to the server introduction.
- The Enter key invokes the default Connect action when the form permits it.
- The button is disabled while connection or profile loading is busy, and when the RPC URL is blank.
- The torrent command bar, including disabled Start/Pause actions, must not appear before connection.
- Connection errors remain visible within the form; profile selection and Keychain behavior are unchanged.
- The collapsed sidebar can still be revealed.

## After connecting
- The command bar uses one-line controls: Add Torrent with a visible label, followed by compact Start/Pause icon buttons and Disconnect on the right.
- Icons provide localized hover help and accessibility labels. No fixed-width caption text is used.
- Start/Pause are disabled when no torrent is selected, while Add Torrent stays available.
- No duplicate "Torrents" headline appears above the table or in its navigation title.
- Torrent inspection, menu actions, selection and footer status remain unchanged.

## Validation
- CI runs the complete Swift test suite, checks EN/RU dictionaries and builds/signs the arm64 app.
- **Human macOS 27 testing remains required**: verify layout at 840 px and wider, dark/light themes, Russian and English UI, primary click and Enter, saved profiles, connection errors, sidebar collapse and post-connect toolbar.
- Do not mark M1 accepted from CI alone; Keenetic file selection and Move/Rename hardware acceptance (#23, #27) remain open.
