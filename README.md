# TreMana

**Transmission Remote Manager for macOS**

TreMana is a native macOS application for remotely
managing Transmission BitTorrent servers through
the Transmission RPC API.

Designed for macOS 27 and later, with a focus on
native integration, performance, and usability.

## Project status

Early development. Features below describe the
planned application, not currently shipped functionality.

## Planned features

- Native macOS interface using SwiftUI and AppKit
- Support for Transmission RPC servers
- Connection profiles and secure authentication
- Add torrents using magnet links or .torrent files
- Monitor downloads, uploads, peers and trackers
- Start, stop, remove and manage torrents
- Individual file selection
- File download ordering
- Sequential piece downloading where supported
- Independent per-torrent download mode settings
- Transfer speed limits and server settings
- Search, sorting and configurable table columns
- macOS notifications
- Finder integration for accessible network shares

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
