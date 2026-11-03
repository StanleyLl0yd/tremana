# TreMana auto-refresh preferences (macOS 27)

Accessible from the standard app **Settings…** menu (Cmd+,).

User-facing options:
- **Automatically refresh torrent information**: enabled by default.
- **Refresh mode**: Adaptive (default) / Fixed.
- **Fixed interval**: 5, 10, 15 or 30 seconds. Default 10 seconds if fixed
  mode is selected or an invalid stored value is encountered.

Policy:
- Adaptive foreground: 5 seconds during downloading/verifying; otherwise 15.
- Inactive/background: 30 seconds regardless of mode (actual execution can
  pause if macOS suspends TreMana).
- After a failed RPC poll: at least 30 seconds to avoid hammering Keenetic.
- A manual Refresh and post-mutation refresh are always available and
  immediate regardless of the auto-refresh toggle.
- A settings change cancels the old polling loop through SwiftUI \`.task(id:)\`
  and creates a new one only if enabled and connected.
- Returning an already connected window to the foreground triggers one
  immediate refresh (if auto-refresh enabled), then the adaptive cycle resumes.

Settings live in macOS UserDefaults with \`com.sl.tremana.refresh.*\` keys.
No passwords, RPC data or torrent content are written there. No daemon
configuration or upload/download policy is changed.

Acceptance on real Keenetic:
1. Adaptive: active progress/rates change without manual Refresh.
2. Stop active torrents: idle cadence settles to ~15 seconds.
3. Inactive app: no excessive RPC polling; macOS suspension is expected.
4. Disable Auto Refresh: progress freezes until manual Refresh.
5. Fixed 10 seconds: updates at a stable cadence while the window is active.
6. Quit and reopen: settings persist; Disconnect stops all polling.


## macOS foreground detection hardening

`scenePhase.active` alone does not guarantee that a Mac window is focused.
The polling view additionally uses SwiftUI `EnvironmentValues.appearsActive`
(current API replacing deprecated `controlActiveState`) to decide whether
the window should use the 5/15 second cadence or inactive 30-second cadence.
When the window regains active appearance, TreMana refreshes once immediately.
The app uses a single `Window` scene rather than a multiwindow `WindowGroup`
to avoid competing auto-refresh loops sharing one Transmission connection.
