const std = @import("std");
const libself = @import("libself");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

test "session scenario case A: discovery over session transport yields direct route" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const transport = @import("../discovery/session_transport.zig").SessionTransport{
        .client_id = "node-client",
        .server_id = "mesh-discovery",
        .client = .{ .id = "node-client", .bus = &bus },
        .server = .{ .id = "mesh-discovery", .bus = &bus },
        .handler = .{ .store = &store },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xb1} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.210", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{};
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    try transport.requestPublish(std.testing.allocator, 11, record);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 11);

    try transport.requestLookup(std.testing.allocator, 12, record.node_id);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    var parsed = try transport.recvLookup(std.testing.allocator, 12);
    defer parsed.deinit();

    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{};
    const resolved = ResolvedPeer{
        .record = parsed.record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
    const plan = try @import("../mesh.zig").resolveRoutes(std.testing.allocator, resolved, .{});
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.direct, plan.decision);
}
