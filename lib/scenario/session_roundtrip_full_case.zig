const std = @import("std");
const libself = @import("libself");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

test "session roundtrip full case covers discovery signaling and relay fallback path" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const discovery = @import("../discovery/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-discovery",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-discovery", .bus = &bus },
        .handler = .{ .store = &store },
    };
    var exchange = @import("../signaling/exchange.zig").Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = @import("../signaling/rendezvous.zig").Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();
    const signaling = @import("../signaling/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    const relay = @import("../relay/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xb4} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.213", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-full", .relay_address = "relay.example.net:8443", .priority = 9 },
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

    try discovery.publishRoundTrip(std.testing.allocator, 200, record, .{ .max_attempts = 2 });
    var looked = try discovery.lookupRoundTrip(std.testing.allocator, 201, record.node_id, .{ .max_attempts = 2 });
    defer looked.deinit();

    try signaling.roundTrip(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 202,
        .payload = "",
    }, .{ .max_attempts = 2 });
    try signaling.roundTrip(std.testing.allocator, .{
        .kind = .setup_payload,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 203,
        .payload = "ice:offer",
    }, .{ .max_attempts = 2 });

    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 9 },
    };
    const resolved = ResolvedPeer{
        .record = looked.record,
        .direct_routes = &direct,
        .relay_routes = &relay_routes,
    };
    const plan = try @import("../mesh.zig").resolveRoutes(std.testing.allocator, resolved, .{
        .direct_disabled = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.relay, plan.decision);

    const opened = try relay.roundTrip(std.testing.allocator, .{
        .kind = .open,
        .session_id = 204,
        .payload = "node-b",
    }, .{ .max_attempts = 2 }, true);
    try std.testing.expectEqual(@import("../relay/protocol.zig").MessageKind.accept, opened.kind);
}
