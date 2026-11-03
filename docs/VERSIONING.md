# Version and release policy

TreMana uses MAJOR.MINOR.PATCH:
- PATCH (0.1.1): compatible fixes, maintenance and security patches.
- MINOR (0.2.0): meaningful new features and additive UI improvements.
- MAJOR (1.0.0 onward): stability milestone or significant incompatible changes. The pre-1.0 series may contain carefully documented minor-level incompatibilities.

The user decides when a milestone warrants a release. PR merges alone do not change versions.

For a release, change release/VERSION and Config/Info.plist CFBundleShortVersionString together, increment CFBundleVersion, and write docs/releases/vX.Y.Z.md. Merge a reviewed PR to protected main. A dedicated GitHub Actions workflow triggers when release/VERSION changes, runs the full test suite and exact-commit packaging, verifies the app, and publishes an immutable-in-intent GitHub Release with ZIP and matching SHA-256 checksum.

A published release must never be silently overwritten or retagged; ship a new version instead.

Stable direct ZIP format:
https://github.com/StanleyLl0yd/tremana/releases/download/vX.Y.Z/TreMana-vX.Y.Z-macOS27-arm64.zip

The current CI uses ad-hoc signing only; Developer ID and Apple notarization are not set up. These releases must never be represented as notarized.

If publication fails after a successful package build, fix the release workflow via
another reviewed PR and update release/REQUEST to a new attempt marker. That
triggers a retry on protected main without changing the semantic version or
retagging any published release. Existing tags pointing to another commit
are treated as hard errors, never forcibly moved.
