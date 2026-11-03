# TreMana — Roadmap

## M0 — Foundation

- Establish native macOS project structure
- Define application architecture
- Implement Transmission RPC compatibility layer
- Verify Transmission 3.00 / RPC 16 behavior
- Define test fixtures and CI

## M1 — Core remote client

- Connection profiles
- Torrent list and details
- Add and remove torrents
- Start, stop and verify torrents
- File selection and transfer statistics
- Native macOS user interface

## M2 — Advanced download control

- Strict file queue
- Persisted ordering and recovery
- Sequential piece mode capability detection
- Independent download mode settings
- Robust handling of reconnects and failures

## M3 — macOS integration and release

- Menu bar integration
- Notifications and keyboard shortcuts
- Finder and SMB integration
- Accessibility and localization
- Performance and security verification
- Release packaging

## Quality gates

After every milestone:

- Full repository-wide code review
- Security audit
- Refactoring review
- Automated test verification
- Documentation review
- Acceptance before milestone closure
