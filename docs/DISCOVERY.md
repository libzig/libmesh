# Discovery Subsystem

## Responsibilities

- publish peer records
- lookup peer records by `NodeId`
- refresh existing records
- withdraw records
- return signed records for consumers

## Data Model

Discovery stores `PeerRecord` values containing:

- identity binding (`node_id`, optional `did`)
- direct endpoints
- relay hints
- signature and expiry metadata

## Store Behavior

`InMemoryStore`:

- verifies signatures before accepting records
- deep-copies records on publish/refresh
- replaces existing records by `node_id`
- frees owned memory on replace/withdraw/deinit

## Protocol

Request/response frame:

```text
kind|correlation_id|node_hex|payload
```

Kinds:

- `publish`
- `lookup`
- `refresh`
- `withdraw`
- `response`

Validation rules:

- `node_hex` must be canonical lowercase 64-char hex
- delimiter (`|`) is not allowed in `node_hex` or payload fields
- method payload semantics are strict:
  - `publish`/`refresh` require non-empty payload
  - `lookup`/`withdraw` require empty payload

## Server Rules

- `publish`: parse signed wire payload, derive signer key from `did:key`, validate and insert
- `lookup`: return signed wire payload or `not_found`
- `refresh`: parse and verify updated signed record, replace previous value
- `withdraw`: remove entry if present
- `publish`/`refresh`: reject if envelope `node_hex` does not match signed record `node_id`
- reject publish timestamps with excessive future skew relative to local clock

## Client Helpers

Client helpers support:

- message builders for `publish`, `lookup`, `refresh`, `withdraw`
- parsing `lookup` responses back into signed peer records

## Future Work

- pluggable persistent discovery backend
- expiration sweep scheduler
- admission policy and rate controls
