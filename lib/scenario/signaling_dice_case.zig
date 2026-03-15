const std = @import("std");
const libself = @import("libself");
const mesh_api = @import("../mesh.zig");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

fn resolvedFromRecord(record: @import("../peer/peer_record.zig").PeerRecord) ResolvedPeer {
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 1 },
    };
    return .{
        .record = record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "scenario case B uses signaling and plans signaling_then_direct route" {
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0xa2} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.201", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-case-b", .relay_address = "relay.example.net:7443", .priority = 1 },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 100,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try mesh_api.publishSelf(&store, key_pair.public_key, record, 110);

    var exchange = @import("../signaling/exchange.zig").Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = @import("../signaling/rendezvous.zig").Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();
    try mesh_api.signalPeer(&exchange, &rendezvous, "node-a", "node-b", 42, "ice:local-candidate");
    const env = exchange.recv("node-b").?;
    defer {
        std.testing.allocator.free(env.from_node);
        std.testing.allocator.free(env.to_node);
    }
    try std.testing.expectEqualStrings("ice:local-candidate", env.message.payload);

    const loaded = try mesh_api.lookupPeer(&store, key_pair.public_key, record.node_id);
    const resolved = resolvedFromRecord(loaded);
    const plan = try mesh_api.resolveRoutes(std.testing.allocator, resolved, .{
        .needs_traversal = true,
        .dice_available = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.signaling_then_direct, plan.decision);
}
