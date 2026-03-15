# libmesh

`libmesh` is a QUIC-native peer reachability layer for Zig.

It provides:

- identity-bound peer discovery
- setup signaling between peers
- authenticated relay fallback

## Stack Position

```text
libself  -> who is this peer?
libmesh  -> where is this peer and how do I reach them?
libdice  -> can I establish a direct path?
libfast  -> run QUIC on the chosen path
```

`libmesh` depends directly on:

- `libself`
- `libfast`

`libmesh` does not directly depend on:

- `libdice`
- `libflux`
- `liblink`

## Package Shape

```text
libmesh
  ├── discovery
  ├── signaling
  ├── relay
  ├── routing
  └── integration
```

## Public API

`lib/mesh.zig` exposes high-level entry points:

- `publishSelf(...)`
- `lookupPeer(...)`
- `lookupPeerAt(...)`
- `expirePeers(...)`
- `signalPeer(...)`
- `openRelayRoute(...)`
- `resolveRoutes(...)`
- `connectPeerViaDriver(...)`
- `connectPeerViaDriverDefault(...)`

## Route Boundary

- `libmesh` carries peer metadata, signaling, and relay fallback.
- `libdice` performs ICE/STUN/TURN direct path establishment externally.
- `libfast` runs QUIC over direct or relayed route.

## Connection Policy

Default route policy is:

1. direct endpoint
2. signaling + external `libdice` when traversal is needed and available
3. relay fallback when direct path cannot be used

## Build And Test

```bash
make build
make test
```

## Examples

See [docs/EXAMPLES.md](docs/EXAMPLES.md) for scenario-driven example entry points.
