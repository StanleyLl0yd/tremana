# TreMana engineering rules

- Work in GitHub branches and pull requests. Do not modify main directly.
- TreMana is a native macOS 27 remote client for Transmission, not a torrent engine.
- Prefer up-to-date stable Swift, Xcode and Apple frameworks; minimize dependencies.
- Maintain legacy Transmission 3.00 / RPC 16 compatibility.
- Do not imply unsupported capabilities are functional.
- Sequential piece download and strict per-file queue are independent requirements.
- Never implement file order by assigning high/medium/low file priorities.
- Do not add category management.
- Never persist or log plaintext credentials. Preserve TLS verification.
- Protect user torrent state: no destructive RPC action without explicit UI intent.
- Add regression tests for behavior and protocol compatibility.
- After each milestone perform a full repository-wide audit, security review,
  code review and refactoring pass (not merely the diff). Record results and CI
  evidence before accepting a milestone.
- English-only code comments, concise documentation and focused commits.
