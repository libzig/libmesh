const std = @import("std");
const libself = @import("libself");
const MeshError = @import("common/error.zig").MeshError;
const PeerRecord = @import("peer/peer_record.zig").PeerRecord;
const ResolvedPeer = @import("peer/resolved_peer.zig").ResolvedPeer;
const discovery = @import("discovery/service.zig");
const store_mod = @import("discovery/store.zig");
const signaling = @import("signaling/service.zig");
const signaling_exchange = @import("signaling/exchange.zig");
const signaling_rendezvous = @import("signaling/rendezvous.zig");
const relay_server_mod = @import("relay/server.zig");
const relay_service_mod = @import("relay/service.zig");
const routing_policy = @import("routing/policy.zig");
const routing_orchestrator = @import("routing/orchestrator.zig");

pub fn publishSelf(
    store: *store_mod.InMemoryStore,
    signer_public_key: libself.identity.PublicKey,
    record: PeerRecord,
    now_ms: u64,
) MeshError!void {
    const service = discovery.Service{
        .store = store,
        .signer_public_key = signer_public_key,
    };
    try service.publish(record, now_ms);
}

pub fn lookupPeer(store: *store_mod.InMemoryStore, signer_public_key: libself.identity.PublicKey, node_id: libself.NodeId) MeshError!PeerRecord {
    const service = discovery.Service{
        .store = store,
        .signer_public_key = signer_public_key,
    };
    return service.lookup(node_id);
}

pub fn signalPeer(
    exchange: *signaling_exchange.Exchange,
    rendezvous: *signaling_rendezvous.Rendezvous,
    from_node: []const u8,
    to_node: []const u8,
    correlation_id: u64,
    payload: []const u8,
) MeshError!void {
    const service = signaling.Service{
        .exchange = exchange,
        .rendezvous = rendezvous,
    };
    try service.sendSetupPayload(from_node, to_node, correlation_id, payload);
}

pub fn openRelayRoute(
    server: *relay_server_mod.Server,
    id: u64,
    source_public_key: libself.identity.PublicKey,
    source_did: []const u8,
    target_public_key: libself.identity.PublicKey,
    target_did: []const u8,
) MeshError!relay_server_mod.OpenResult {
    const service = relay_service_mod.Service{ .server = server };
    return service.open(id, source_public_key, source_did, target_public_key, target_did);
}

pub fn resolveRoutes(
    allocator: std.mem.Allocator,
    peer: ResolvedPeer,
    runtime: routing_policy.Runtime,
) MeshError!routing_orchestrator.Plan {
    return routing_orchestrator.buildPlan(allocator, .{}, peer, runtime);
}

test "mesh API publishes and looks up signed peer records" {
    var store = store_mod.InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x88} ** 32);
    const endpoints = [_]@import("peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.120", .port = 4433 },
    };
    const hints = [_]@import("peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-api", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try publishSelf(&store, key_pair.public_key, record, 20);

    const loaded = try lookupPeer(&store, key_pair.public_key, record.node_id);
    try std.testing.expectEqual(record.node_id.toHex(), loaded.node_id.toHex());
}

test "mesh API signals peer setup payloads" {
    var exchange = signaling_exchange.Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = signaling_rendezvous.Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    try signalPeer(&exchange, &rendezvous, "node-a", "node-b", 1, "candidate");
    const env = exchange.recv("node-b").?;
    defer {
        std.testing.allocator.free(env.from_node);
        std.testing.allocator.free(env.to_node);
    }
    try std.testing.expectEqualStrings("candidate", env.message.payload);
}

test "mesh API opens relay routes and resolves routes" {
    var matcher = @import("relay/matcher.zig").Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var relay_server = relay_server_mod.Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 4,
        .require_authenticated = true,
    });
    defer relay_server.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0x89} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0x8a} ** 32);
    const source_did = try libself.DidKey.fromKeyPair(source).encode(std.testing.allocator);
    defer std.testing.allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(std.testing.allocator);
    defer std.testing.allocator.free(target_did);

    const open = try openRelayRoute(
        &relay_server,
        99,
        source.public_key,
        source_did,
        target.public_key,
        target_did,
    );
    try std.testing.expect(open.session.authenticated);

    const endpoints = [_]@import("peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.55", .port = 4433 },
    };
    const hints = [_]@import("peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-api2", .relay_address = "relay.example.net:7443" },
    };
    const direct_routes = [_]@import("peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 1 },
    };
    const relay_routes = [_]@import("peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 1 },
    };
    const resolved = ResolvedPeer{
        .record = .{
            .node_id = libself.NodeId.fromPublicKey(source.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &hints,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };
    const plan = try resolveRoutes(std.testing.allocator, resolved, .{});
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(routing_policy.Decision.direct, plan.decision);
}
