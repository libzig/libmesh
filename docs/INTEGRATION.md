# Integration Notes

## libself Integration

`libmesh` uses `libself` for:

- `NodeId` derivation from public keys
- `did:key` encode/parse
- peer record signing and verification
- relay session identity validation
- trust bridge for policy decisions

## libfast Integration

`libmesh` uses `libfast` for:

- direct endpoint target materialization
- relay target materialization
- route ordering handoff
- control-session framing and capability/version negotiation
- retry/backoff helpers for control-plane operations

## libdice Contract

`libmesh` does not call `libdice` directly.

Expected external orchestration contract:

1. `libmesh` resolves peer metadata and route candidates.
2. If traversal is needed, `libmesh` signaling carries setup payloads between peers.
3. Higher-level node/orchestrator invokes `libdice` externally.
4. `libfast` runs QUIC on the selected direct path.
5. If direct cannot be established, `libmesh` relay fallback is used.

Decision mapping used in `libmesh.integration.libdice_contract`:

- `direct`: no signaling, no `libdice`, no forced relay.
- `signaling_then_direct`: signaling enabled, external `libdice` expected, relay fallback allowed.
- `relay`: no signaling, no `libdice`, relay required.

Public orchestration helpers:

- `libmesh.integration.node_orchestrator.connect(...)`
- `libmesh.integration.node_orchestrator.connectAndOpenSession(...)`
- `libmesh.connectPeerViaDriver(...)`
- `libmesh.connectPeerViaDriverDefault(...)`

## Compatibility Rules

- major protocol version mismatch in control session negotiation is rejected
- negotiated capabilities are intersection of local/remote support
- control payloads reject delimiter (`|`) and enforce a bounded max payload size
