# TreMana

**Native Transmission remote manager for macOS.**

**English** · [Русский](README.ru.md)

TreMana puts torrent management for a remote **Transmission** server into a clean, fast, native Mac app. Keep Transmission on a NAS, router, or another machine — monitor and control it from your Mac.

## What you get

- **Fast overview:** progress, transfer speeds, ETA, ratio, seeds, leeches, and reorderable, hideable columns.
- **Torrent controls:** add a magnet or `.torrent`, start, pause, verify downloaded pieces, reannounce, or remove torrents; deletion of remote data requires confirmation.
- **Detailed inspection:** files, trackers, peers, and web seeds, with a resizable information pane.
- **Secure connections:** saved server profiles with passwords in macOS Keychain; HTTPS supported.
- **Native experience:** SwiftUI, system appearance, adaptive auto-refresh, and no third-party UI runtime.

<sub>File selection and remote Move/Rename are planned, not available in v0.1.0. Sequential piece downloads are not supported by Transmission 3.00 RPC 16.</sub>

## Download

**[Download TreMana 0.1.0 for macOS — ZIP](https://github.com/StanleyLl0yd/tremana/releases/download/v0.1.0/TreMana-v0.1.0-macOS27-arm64.zip)**

**Requires:** macOS **27 or newer**, **Apple Silicon (arm64)**, and access to a Transmission server (tested with **3.00 / RPC 16**).

Unzip, move `TreMana.app` to Applications, and open it. The v0.1.0 binary is **ad-hoc signed, not Apple notarized**; macOS may ask for a one-time approval in **System Settings → Privacy & Security**. Do not disable Gatekeeper globally.

Keep your Transmission RPC port restricted to trusted networks. Prefer HTTPS or a trusted VPN; use plain HTTP only on a trusted LAN.

## Links

[Release notes](docs/releases/v0.1.0.md) · [Issues & requests](https://github.com/StanleyLl0yd/tremana/issues) · [Security](SECURITY.md) · [MIT license](LICENSE)

TreMana is an independent third-party client, not affiliated with Transmission or Keenetic.
