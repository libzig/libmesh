# libmesh Architecture

## Role

`libmesh` is the peer reachability layer:

1. find peer by identity
2. exchange setup information
3. use relay fallback when direct path fails

## Top-Level Structure

```text
libmesh
  ├── discovery
  ├── signaling
  └── relay
```

## Dependency Boundaries

Direct dependencies:

- `libself`
- `libfast`

No direct dependency:

- `libdice`
- `libflux`
- `liblink`

## Control And Data Planes

- discovery + signaling: control plane
- relay: fallback data plane

## Connection Cases

### Direct path works

1. lookup peer record
2. attempt direct QUIC endpoint
3. authenticate with `libself`

### Direct path needs traversal

1. lookup peer record
2. exchange setup payloads in signaling
3. external orchestrator invokes `libdice`
4. run QUIC over resulting path

### Direct path fails

1. lookup peer record and relay hints
2. connect both peers to relay
3. bridge streams/datagrams through relay

## Routing Rule

Decision precedence:

1. direct
2. signaling + direct attempt
3. relay fallback
