# libmesh Specification (v0.1 Draft)

## Scope

`libmesh` covers:

- peer discovery
- setup signaling
- relay fallback

`libmesh` does not implement ICE/STUN/TURN.

## Identity

- Peer identity is anchored to `libself` (`NodeId`, `did:key`).
- Peer records are signed and verified with `libself`.
- Relay session admission requires identity-authenticated endpoints.

## Peer Record

`PeerRecord` fields:

- `node_id`
- optional `did`
- `published_at_ms`
- `expires_at_ms`
- `endpoints[]`
- `relay_hints[]`
- `signature`

Encoding:

- canonical payload for signing
- wire payload includes canonical fields plus `sig=<hex>`

## Discovery Protocol

Message kinds:

- `publish`
- `lookup`
- `refresh`
- `withdraw`
- `response`

Frame format:

```text
kind|correlation_id|node_hex|payload
```

Server rules:

- `publish`: parse signed wire record, verify signer from `did:key`, store record
- `lookup`: return signed wire record if found, else `not_found`
- `refresh`: parse + verify + replace existing record
- `withdraw`: remove record if present

## Signaling Protocol

Message kinds:

- `connect_request`
- `connect_accept`
- `connect_reject`
- `candidate`
- `setup_payload`

Frame format:

```text
kind|from_node|to_node|correlation_id|payload
```

`setup_payload` is intentionally generic so external orchestrators can carry ICE-related data for `libdice`.

## Relay Protocol

Message kinds:

- `open`
- `accept`
- `deny`
- `stream_chunk`
- `datagram`
- `close`

Frame format:

```text
kind|session_id|payload
```

Relay flow:

1. Open authenticated session
2. Match reverse peer pair
3. Forward streams (required)
4. Forward datagrams (optional)

## Routing Policy

Decision order:

1. direct
2. signaling_then_direct (when traversal orchestration is needed)
3. relay fallback

The external node/client may invoke `libdice` after signaling when direct traversal is required.

## Integration Contracts

- `libmesh -> libself`: identity/signature/trust
- `libmesh -> libfast`: QUIC transport target materialization and control framing
- `libmesh -X-> libdice`: no direct dependency; consumed externally by orchestrator
