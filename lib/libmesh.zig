const libself = @import("libself");
const libfast = @import("libfast");

pub fn hello() []const u8 {
    return "hello from libmesh";
}

pub const api = @import("mesh.zig");

pub const Foundation = struct {
    pub const NodeId = libself.NodeId;
    pub const KeyPair = libself.identity.KeyPair;
    pub const DidKey = libself.DidKey;
};

pub const common = struct {
    pub const errors = @import("common/error.zig");
    pub const time = @import("common/time.zig");
    pub const version = @import("common/version.zig");
    pub const caps = @import("common/caps.zig");
};

pub const peer = struct {
    pub const endpoint = @import("peer/endpoint.zig");
    pub const peer_record = @import("peer/peer_record.zig");
    pub const relay_hint = @import("peer/relay_hint.zig");
    pub const resolved_peer = @import("peer/resolved_peer.zig");
    pub const route_candidate = @import("peer/route_candidate.zig");
};

pub const auth = struct {
    pub const record_signer = @import("auth/record_signer.zig");
    pub const record_verifier = @import("auth/record_verifier.zig");
    pub const trust_bridge = @import("auth/trust_bridge.zig");
};

pub const discovery = struct {
    pub const client = @import("discovery/client.zig");
    pub const expire = @import("discovery/expire.zig");
    pub const lookup = @import("discovery/lookup.zig");
    pub const protocol = @import("discovery/protocol.zig");
    pub const publish = @import("discovery/publish.zig");
    pub const refresh = @import("discovery/refresh.zig");
    pub const service = @import("discovery/service.zig");
    pub const server = @import("discovery/server.zig");
    pub const store = @import("discovery/store.zig");
    pub const withdraw = @import("discovery/withdraw.zig");
};

pub const signaling = struct {
    pub const client = @import("signaling/client.zig");
    pub const exchange = @import("signaling/exchange.zig");
    pub const protocol = @import("signaling/protocol.zig");
    pub const rendezvous = @import("signaling/rendezvous.zig");
    pub const service = @import("signaling/service.zig");
    pub const server = @import("signaling/server.zig");
};

pub const integration = struct {
    pub const control_session = @import("integration/control_session.zig");
    pub const libdice_contract = @import("integration/libdice_contract.zig");
    pub const libfast = @import("integration/libfast.zig");
    pub const libself = @import("integration/libself.zig");
    pub const retry = @import("integration/retry.zig");
    pub const session_bus = @import("integration/session_bus.zig");
    pub const session_endpoint = @import("integration/session_endpoint.zig");
};

pub const routing = struct {
    pub const orchestrator = @import("routing/orchestrator.zig");
    pub const policy = @import("routing/policy.zig");
};

pub const relay = struct {
    pub const bridge_datagrams = @import("relay/bridge_datagrams.zig");
    pub const bridge_streams = @import("relay/bridge_streams.zig");
    pub const client = @import("relay/client.zig");
    pub const matcher = @import("relay/matcher.zig");
    pub const policy = @import("relay/policy.zig");
    pub const protocol = @import("relay/protocol.zig");
    pub const service = @import("relay/service.zig");
    pub const server = @import("relay/server.zig");
    pub const session = @import("relay/session.zig");
};

pub const scenario = struct {
    pub const direct_case = @import("scenario/direct_case.zig");
    pub const failure_modes = @import("scenario/failure_modes.zig");
    pub const relay_fallback_case = @import("scenario/relay_fallback_case.zig");
    pub const signaling_dice_case = @import("scenario/signaling_dice_case.zig");
};

test "libmesh foundation imports libself and libfast" {
    const std = @import("std");
    try std.testing.expectEqualStrings("hello from libmesh", hello());
    try std.testing.expect(libfast.version.len > 0);

    const key_pair = try Foundation.KeyPair.fromSeed([_]u8{0x11} ** 32);
    const node_id = Foundation.NodeId.fromPublicKey(key_pair.public_key);
    try std.testing.expect(node_id.toHex().len == 64);

    const allocator = std.testing.allocator;
    const did = try Foundation.DidKey.fromKeyPair(key_pair).encode(allocator);
    defer allocator.free(did);
    try std.testing.expect(std.mem.startsWith(u8, did, "did:key:"));

    _ = common.errors;
    _ = common.time;
    _ = common.version;
    _ = common.caps;
    _ = api;
    _ = peer.endpoint;
    _ = peer.peer_record;
    _ = peer.relay_hint;
    _ = peer.resolved_peer;
    _ = peer.route_candidate;
    _ = auth.record_signer;
    _ = auth.record_verifier;
    _ = auth.trust_bridge;
    _ = discovery.client;
    _ = discovery.expire;
    _ = discovery.lookup;
    _ = discovery.protocol;
    _ = discovery.publish;
    _ = discovery.refresh;
    _ = discovery.service;
    _ = discovery.server;
    _ = discovery.store;
    _ = discovery.withdraw;
    _ = signaling.client;
    _ = signaling.exchange;
    _ = signaling.protocol;
    _ = signaling.rendezvous;
    _ = signaling.service;
    _ = signaling.server;
    _ = relay.bridge_datagrams;
    _ = relay.client;
    _ = integration.libfast;
    _ = integration.libself;
    _ = integration.control_session;
    _ = integration.libdice_contract;
    _ = integration.retry;
    _ = integration.session_bus;
    _ = integration.session_endpoint;
    _ = routing.orchestrator;
    _ = routing.policy;
    _ = relay.bridge_streams;
    _ = relay.matcher;
    _ = relay.policy;
    _ = relay.protocol;
    _ = relay.service;
    _ = relay.server;
    _ = relay.session;
    _ = scenario.direct_case;
    _ = scenario.failure_modes;
    _ = scenario.relay_fallback_case;
    _ = scenario.signaling_dice_case;
}
