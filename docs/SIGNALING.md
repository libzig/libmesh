# Signaling Subsystem

## Responsibilities

- connection request / accept / reject flow
- rendezvous correlation tracking
- setup payload exchange between peers
- generic payload transport for external traversal orchestrators

## Protocol

Message frame:

```text
kind|from_node|to_node|correlation_id|payload
```

Kinds:

- `connect_request`
- `connect_accept`
- `connect_reject`
- `candidate`
- `setup_payload`

Validation rules:

- `from_node` and `to_node` must be non-empty and whitespace-free
- delimiter (`|`) is not allowed in node identifiers or payload
- correlation id must be non-zero

## Exchange And Rendezvous

- `Exchange` is the in-memory message queue between peers
- `Rendezvous` tracks pending requests by correlation id
- `Server.processNext` consumes queued messages and updates rendezvous state

## Service API

`signaling/service.zig` provides high-level operations:

- `requestConnect(...)`
- `acceptConnect(...)`
- `rejectConnect(...)`
- `sendSetupPayload(...)`
- `processNext(...)`

## Boundary With libdice

Signaling payloads are generic by design.

`libmesh` only transports setup data; it does not run ICE checks internally.
External orchestrators can pass ICE-related payloads through signaling and invoke `libdice` outside `libmesh`.

## Future Work

- authentication tags on signaling frames
- replay protection and nonce binding
- transport-level multiplexing over live QUIC control sessions
