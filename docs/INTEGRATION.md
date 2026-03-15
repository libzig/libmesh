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

Expected external orchestration:

1. `libmesh` lookup + signaling
2. external call to `libdice` for direct traversal attempt
3. run QUIC over winning route
4. fallback to `libmesh` relay route if direct path fails

## Compatibility Rules

- major protocol version mismatch in control session negotiation is rejected
- negotiated capabilities are intersection of local/remote support
