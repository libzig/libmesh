# Changelog

## [0.0.2] - 2026-03-15

### <!-- 0 -->⛰️  Features

- Extend orchestrator demo with driver-backed session opens
- Add request expectation helpers to session endpoints
- Add correlation-bound lookup response parsing
- Add default-runtime driver connect convenience API
- Add nowMs helper for runtime timestamp checks
- Expose connectPeerViaDriver orchestration API
- Validate expected session id in open responses
- Fallback to relay when direct session open fails
- Open sessions through libfast adapter targets
- Support bracketed ipv6 relay hints
- Add openAny target fallback helper
- Export libfast adapter session shim
- Add source-bound request/response exchange variants
- Add validated retry behavior for roundtrip control
- Add validated retry roundtrip and idempotent request handling
- Add validated response retry behavior for roundtrips
- Add response-validated retry exchange path
- Add endpoint request/response convenience APIs
- Add source-filtered receive and queue introspection to session bus
- Add session-control orchestration path
- Add retryable roundtrip session transport API
- Add retryable roundtrip session transport API
- Add retryable roundtrip session transport APIs
- Add retryable request-response exchange helper
- Enforce capability and version negotiation in session transport
- Enforce capability and version negotiation in session transport
- Enforce capability and version negotiation in session transport
- Add control negotiation guard helper
- Add orchestrator example and smoke test target
- Add high-level connection orchestrator
- Add session-transport adapter with open ack policy
- Add session-transport adapter and pump
- Add session-transport adapter over control envelopes
- Add control envelope endpoint over session bus
- Add in-memory control session bus
- Add runnable examples with smoke tests in build
- Codify external libdice orchestration contract
- Add lookupPeerAt and expirePeers operations
- Add freshness-aware service lookup and expire
- Add explicit expire operation module
- Add lookupAt and pruneExpired lifecycle helpers
- Support publish refresh and own stored records
- Add publish refresh builders and lookup parse
- Add signed wire payload encode/decode for peer records
- Add retry and backoff helper
- Add control-session framing and negotiation
- Add unified mesh reachability API surface
- Add connection plan orchestrator
- Add direct-signaling-relay decision policy
- Add high-level relay service API
- Add high-level signaling service API
- Add high-level discovery service lifecycle API
- Add libself identity and signature bridge
- Add client matcher server and admission policy
- Add relay protocol codec and datagram bridge
- Add client server request accept coordination
- Add peer setup exchange channel
- Add protocol client and server handlers
- Add publish lookup refresh withdraw operation modules
- Add discovery protocol message codec
- Add trust bridge over libself trust store
- Add record verifier with signature checks
- Add libself-backed record signer wrapper
- Add libself-authenticated session open and stream bridge
- Add libfast connection target materialization
- Add resolved peer routes and candidate ordering
- Add rendezvous request accept reject flow
- Add protocol message model and codec
- Add verified in-memory publish lookup refresh withdraw
- Add canonical peer records with libself sign/verify
- Add endpoint and relay hint models with validation
- Add core error time version and capability modules
- Wire libself and libfast dependencies
- Init

### <!-- 1 -->🐛 Bug Fixes

- Enforce session id consistency in recv path
- Enforce request payload rules by method
- Surface relay fallback errors after direct failure
- Bind payload correlation to envelope in roundtrip validation
- Reject unknown fields in wire payload parser
- Cap control-session payload size
- Enforce open/close payload protocol semantics
- Reject empty or whitespace peer identifiers
- Require canonical 64-char node hex in protocol decode
- Avoid duplicating exhausted route targets
- Reject empty targets when building open requests
- Reject delimiter characters in control payloads
- Reject delimiter characters in protocol payload
- Reject delimiter characters in encoded fields
- Reject delimiter characters in encoded fields
- Verify lookup response node hex against peer record
- Enforce node_hex and record node_id consistency
- Guard publish timestamps against excessive future skew
- Validate payload session id in roundtrip responses
- Reject duplicate session ids at server open
- Clear matcher pending state when closing sessions
- Reject duplicate pending matcher session ids
- Preserve FIFO ordering in session bus receive
- Reject future published timestamps during validation
- Reject duplicate fields in wire payload parser
- Validate did:key against node id
- Enforce did:key match during record verification
- Canonicalize relay hint order in signed payload
- Canonicalize endpoint order in signed payload
- Skip invalid relay hints in target resolution
- Skip invalid direct endpoint hints in target resolution
- Bind roundtrip responses to expected server source
- Bind roundtrip responses to expected server source
- Bind roundtrip responses to expected server source
- Improve target materialization and fallback handling

### <!-- 3 -->📚 Documentation

- Align protocol docs with current validation rules
- Add consolidated examples guide
- Add orchestrator example README
- Document orchestration contract and final API surface
- Add relay integration docs and example scaffolds
- Add signaling protocol and rendezvous guide
- Add discovery protocol and store behavior guide
- Add architecture overview and routing cases
- Add protocol and boundary specification draft
- Add project README with architecture and boundaries

### <!-- 6 -->🧪 Testing

- Cover orchestrator relay outcome without libdice
- Cover relay datagram forwarding flow
- Add signaling reject-flow coverage
- Cover freshness lookup and expiry pruning flow
- Cover libdice-unavailable fallback in case B
- Verify relay decision when libdice is unavailable
- Cover traversal-needed behavior without libdice
- Add full session roundtrip control-plane case
- Add relay fallback case via session transports
- Add signaling traversal case via session transports
- Add direct case via session discovery transport
- Add stale-record and relay-auth failure cases
- Add relay fallback case coverage
- Add signaling plus direct-traversal case
- Add direct-route case coverage

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Changelog file
- Update dependencies to use remote URLs

