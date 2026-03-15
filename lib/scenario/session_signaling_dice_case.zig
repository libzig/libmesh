const std = @import("std");
const libself = @import("libself");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

test "session scenario case B: signaling over session transport yields signaling_then_direct plan" {
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

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xb2} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.211", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-case-b", .relay_address = "relay.example.net:7443", .priority = 3 },
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
    try discovery_transport.requestPublish(std.testing.allocator, 21, record);
    try std.testing.expect(try discovery_transport.pumpServer(std.testing.allocator));
    try discovery_transport.recvAck(std.testing.allocator, 21);

    var signaling_exchange = @import("../signaling/exchange.zig").Exchange.init(std.testing.allocator);
    defer signaling_exchange.deinit();
    var rendezvous = @import("../signaling/rendezvous.zig").Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();
    const signaling_transport = @import("../signaling/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &signaling_exchange,
        .rendezvous = &rendezvous,
    };

    try signaling_transport.send(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 77,
        .payload = "",
    });
    try std.testing.expect(try signaling_transport.pumpServer(std.testing.allocator));
    try signaling_transport.recvAck(std.testing.allocator, 77);

    try signaling_transport.send(std.testing.allocator, .{
        .kind = .setup_payload,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 78,
        .payload = "ice:offer",
    });
    try std.testing.expect(try signaling_transport.pumpServer(std.testing.allocator));
    try signaling_transport.recvAck(std.testing.allocator, 78);

    try discovery_transport.requestLookup(std.testing.allocator, 22, record.node_id);
    try std.testing.expect(try discovery_transport.pumpServer(std.testing.allocator));
    var parsed = try discovery_transport.recvLookup(std.testing.allocator, 22);
    defer parsed.deinit();

    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 3 },
    };
    const resolved = ResolvedPeer{
        .record = parsed.record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
    const plan = try @import("../mesh.zig").resolveRoutes(std.testing.allocator, resolved, .{
        .needs_traversal = true,
        .dice_available = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.signaling_then_direct, plan.decision);
}
