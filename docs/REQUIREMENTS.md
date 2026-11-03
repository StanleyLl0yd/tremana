# TreMana — Requirements

## Target platform

- macOS 27+
- Native SwiftUI and AppKit interface
- Apple Silicon as the primary target
- Latest stable compatible Swift and Xcode

## Server compatibility

Initial compatibility baseline:

- Transmission 3.00
- RPC protocol version 16
- Keenetic-hosted Transmission

RPC capabilities must be detected and validated.
No unsupported operation may appear to succeed.

## Download modes

Two independent per-torrent settings:

### Sequential pieces

Download pieces in sequential order when supported
by the connected Transmission server.

### Strict file queue

Download selected files in their specified order.

The next file becomes eligible only after the current
file has completed.

File priorities must not be used to simulate ordering.

### Combined mode

Both sequential pieces and strict file queue
can be enabled simultaneously when supported.

### Compatibility considerations

Transmission 3.00 does not expose standard RPC
support for sequential piece downloading.

Strict file queue control may be implemented through
files-wanted and files-unwanted RPC operations.

A client-side queue controller must account for
application suspension, disconnection and restart.

## UI principles

- Native macOS appearance and behavior
- Responsive tables and keyboard shortcuts
- Clear connection and transfer status
- No category management
- No unnecessary background activity

## Security

- Store credentials in macOS Keychain
- Validate TLS certificates
- Never log passwords or authentication headers
- Do not expose RPC credentials in diagnostic exports
- Validate remote paths and untrusted metadata
- Avoid insecure remote access defaults
