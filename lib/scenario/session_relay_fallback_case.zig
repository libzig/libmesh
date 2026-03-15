const std = @import("std");
const libself = @import("libself");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

test "session scenario case C: relay fallback path over session transport" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const discovery_transport = @import("../discovery/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-discovery",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-discovery", .bus = &bus },
        .handler = .{ .store = &store },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xb3} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.212", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-case-c", .relay_address = "relay.example.net:8443", .priority = 9 },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try discovery_transport.requestPublish(std.testing.allocator, 31, record);
    try std.testing.expect(try discovery_transport.pumpServer(std.testing.allocator));
    try discovery_transport.recvAck(std.testing.allocator, 31);

    try discovery_transport.requestLookup(std.testing.allocator, 32, record.node_id);
    try std.testing.expect(try discovery_transport.pumpServer(std.testing.allocator));
    var parsed = try discovery_transport.recvLookup(std.testing.allocator, 32);
    defer parsed.deinit();

    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 9 },
    };
    const resolved = ResolvedPeer{
        .record = parsed.record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
    const plan = try @import("../mesh.zig").resolveRoutes(std.testing.allocator, resolved, .{
        .direct_disabled = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.relay, plan.decision);

    const relay_transport = @import("../relay/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };
    try relay_transport.send(std.testing.allocator, .{
        .kind = .open,
        .session_id = 1001,
        .payload = "node-b",
    });
    try std.testing.expect(try relay_transport.pumpServer(std.testing.allocator, true));
    const opened = try relay_transport.recv(std.testing.allocator, 1001);
    try std.testing.expectEqual(@import("../relay/protocol.zig").MessageKind.accept, opened.kind);
}
