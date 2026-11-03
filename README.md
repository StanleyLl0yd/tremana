# TreMana

**Transmission Remote Manager for macOS**

TreMana is a native macOS application for remotely
managing Transmission BitTorrent servers through
the Transmission RPC API.

Designed for macOS 27 and later, with a focus on
native integration, performance, and usability.

## Release

**Latest version: 0.1.0**

[Download TreMana 0.1.0 ZIP directly](https://github.com/StanleyLl0yd/tremana/releases/download/v0.1.0/TreMana-v0.1.0-macOS27-arm64.zip)

macOS 27+ and Apple Silicon. The published app is ad-hoc signed, not Apple
Developer ID signed or notarized. On first launch macOS may require approval
in System Settings > Privacy & Security. Do not disable Gatekeeper globally.

### Available in 0.1.0
- Transmission RPC 16, connection profiles and secure Keychain credentials
- Native torrent list, customizable table columns and automatic refresh
- Torrent Details, Files (view only), Trackers, Peers and Web Seeds
- Magnet / .torrent add, Start, Pause, Verify, Reannounce, Copy Magnet, and guarded removal

### Planned, not yet shipped
- Interactive selection of files to download (#23)
- Remote Move and Rename (#27)
- Strict autonomous file queue, other advanced server controls

Read [release notes](docs/releases/v0.1.0.md) and the
[versioning policy](docs/VERSIONING.md).

## Download modes

TreMana is designed to expose two independent options:

1. Sequential piece downloading
2. Strict file download queue

Either option may be selected independently or together.

Feature availability depends on server capabilities.
Unsupported server-side functionality must be reported
clearly rather than silently simulated.

## Compatibility

Initial target:

- macOS 27+
- Transmission 3.00 / RPC 16

Additional Transmission versions will be evaluated
through compatibility tests.

## Technology

- Swift
- SwiftUI
- AppKit
- Swift Concurrency
- URLSession
- macOS Keychain

Current stable, compatible development tools are preferred.

## Security

Credentials must be stored securely in macOS Keychain.
TLS certificate validation must not be disabled.
Remote connections should use HTTPS or a trusted VPN.

## Development

See [Requirements](docs/REQUIREMENTS.md) and
[Roadmap](docs/ROADMAP.md).

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

TreMana is an independent third-party application.
It is not affiliated with the Transmission or
Keenetic projects.
