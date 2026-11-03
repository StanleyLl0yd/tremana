# M0 connection lifecycle

The observable connection model is located in TreManaCore so its async state
transitions can be verified independently from the SwiftUI view layer.

The \`TransmissionRPCProviding\` protocol supports deterministic test doubles.
The concrete \`TransmissionRPCClient\` remains actor-isolated and retains the
same HTTP 409 handshake, authentication and TLS behavior.

\`disconnect()\` increments a local connection generation, clears server and
torrent data, removes the in-memory form password, and unsets the busy state.
Operations capture the generation on entry and discard replies that arrive
after any disconnect. A stale request never clears the busy state of a newer
connection. This avoids an old response re-establishing a disconnected session.

This is UI state invalidation, not an RPC shutdown: disconnecting TreMana does
not stop the Transmission daemon or its torrents. Outstanding URLSession tasks
can finish or time out but cannot mutate disconnected model state.

Acceptance test #7 is still PENDING until confirmed manually on the Keenetic.
