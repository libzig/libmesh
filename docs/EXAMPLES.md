# Examples

## publish_lookup

Purpose:

1. create and sign a `PeerRecord`
2. publish into discovery
3. lookup by `NodeId`
4. verify identity binding and expiry behavior

Entry point: `examples/publish_lookup/main.zig`

## signal_exchange

Purpose:

1. send connect request/accept/reject over signaling exchange
2. process rendezvous state transitions
3. send setup payloads (for external traversal orchestration)

Entry point: `examples/signal_exchange/main.zig`

## relay_pair

Purpose:

1. open authenticated reverse relay sessions
2. match peers in relay matcher
3. forward streams and datagrams

Entry point: `examples/relay_pair/main.zig`

## orchestrator

Purpose:

1. compute route decisions from peer metadata and runtime flags
2. map signaling/direct/relay outcomes
3. open sessions through the driver-backed connection helper

Entry point: `examples/orchestrator/main.zig`
