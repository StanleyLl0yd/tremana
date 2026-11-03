# Connection controls and macOS appearance

## Connection toolbar

The compact command bar is shown in both connected and disconnected states.
**Connect** and **Disconnect** are always the first two actions at the left;
when their action is not applicable the button remains visible but disabled.

Connect uses only the RPC URL, profile and credentials explicitly configured in
the form / saved profile. It never changes which Transmission daemon is running.
Disconnect invalidates in-flight RPC responses and stops polling; it does not
stop torrents or shut down the daemon. The existing connection form is visible
when disconnected; it no longer repeats the Connect button.

## Appearance

Settings > Appearance offers **System** (default), **Light** and **Dark**.
The setting persists in UserDefaults, and system mode uses native macOS
appearance, including automatic day/night changes. SwiftUI's
preferredColorScheme is applied to both the main Window and the Settings
scene; the rest of the app relies on semantic colors and system materials.

Requires actual Mac acceptance in light and dark, high contrast and reduced
transparency, and connection/disconnection with a stored profile.
