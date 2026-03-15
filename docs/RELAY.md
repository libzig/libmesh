# Relay Subsystem

## Responsibilities

- authenticated relay session open
- peer pair matching for reverse session requests
- stream forwarding
- optional datagram forwarding
- admission policy enforcement

## Protocol

Relay frame:

```text
kind|session_id|payload
```

Kinds:

- `open`
- `accept`
- `deny`
- `stream_chunk`
- `datagram`
- `close`

Validation rules:

- session id must be non-zero
- delimiter (`|`) is not allowed in payload
- `open` requires non-empty payload (target peer identity)
- `close` requires empty payload
- response payload `session_id` must match response correlation id in control envelope

## Components

- `session.zig`: validates DID/public-key bindings and opens authenticated sessions
- `matcher.zig`: pairs reverse sessions (`A->B` with `B->A`)
- `server.zig`: admission and active session lifecycle
- `service.zig`: high-level relay API
- `bridge_streams.zig`: stream forwarding
- `bridge_datagrams.zig`: datagram forwarding
- `policy.zig`: auth and capacity policy

## Relay Behavior

1. peer A opens authenticated session to peer B
2. peer B opens authenticated session to peer A
3. matcher emits pair match
4. relay forwards stream/datagram payloads according to policy

## Security Notes

- session open requires `did:key` and public-key consistency
- unauthenticated session forwarding is denied
- policy can enforce max active sessions and auth requirement
