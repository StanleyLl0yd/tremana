# TreMana architecture — M0

TreMana is a native Transmission RPC client for macOS 27. It does not implement
BitTorrent networking and does not change the server's torrent engine.

## Modules

- TreMana: SwiftUI application, connection screen, torrent table and user feedback.
- TreManaCore: typed Transmission 3.00 / RPC 16-17 transport and queue planning.
- TreManaCoreTests: isolated mock HTTP responses and pure planning tests.
- scripts/package-app.sh: produces an ad-hoc-signed macOS application bundle.

No external package dependencies are needed at M0. No server credentials are
written to disk. They remain in the running RPC client and are cleared from
the connection form after successful connection.

## Transmission protocol

Legacy RPC uses POST JSON, an HTTP 409 challenge carrying
X-Transmission-Session-Id, and a retry with that header. HTTP Basic
authentication is only sent when the user supplies a username. TLS validation
is provided by URLSession and is not bypassed.

HTTP is disabled by default and requires explicit opt-in. This switch is meant
only for trusted local connections; users must not expose unsecured HTTP
Transmission RPC to the public internet.

The current adapter supports legacy RPC versions 16 and 17. Transmission
4.1 uses JSON-RPC 2.0 with snake_case methods and requires a separate adapter.

## Download modes

These are independent desired user settings, not implementations at M0:

1. Sequential pieces. Not provided by Transmission 3.00 / RPC 16.
2. Strict file queue. Requires a persistent controller that reconciles wanted
   files, completion and user-selected order. The pure planner is introduced
   in M0; no automatic queue progression is claimed.

The queue plan uses files-wanted and files-unwanted, never file priority.
An empty file index array in legacy RPC means ALL files; the planner must
never send an empty array to mean none. Cross-file pieces may still share
data at file boundaries.

## Quality

GitHub Actions builds and tests the source on macOS 27 ARM64, packages an
unsigned-for-distribution (ad-hoc signed) app and validates its metadata.
Do not publish the CI artifact as a production release until milestone
acceptance, runtime testing and signing/notarization policy are resolved.
