const std = @import("std");
const libself = @import("libself");
const mesh_api = @import("../mesh.zig");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

fn resolvedFromRecord(record: @import("../peer/peer_record.zig").PeerRecord) ResolvedPeer {
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 9 },
    };
    return .{
        .record = record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "scenario case C falls back to relay and opens authenticated route" {
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xa3} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xa4} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.202", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-case-c", .relay_address = "relay.example.net:8443", .priority = 9 },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(target.public_key),
        .published_at_ms = 100,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, target);
    try mesh_api.publishSelf(&store, target.public_key, record, 110);

    const loaded = try mesh_api.lookupPeer(&store, target.public_key, record.node_id);
    const resolved = resolvedFromRecord(loaded);
    const plan = try mesh_api.resolveRoutes(std.testing.allocator, resolved, .{
        .direct_disabled = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.relay, plan.decision);

    var matcher = @import("../relay/matcher.zig").Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var relay_server = @import("../relay/server.zig").Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 4,
        .require_authenticated = true,
    });
    defer relay_server.deinit();

    const source_did = try libself.DidKey.fromKeyPair(source).encode(std.testing.allocator);
    defer std.testing.allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(std.testing.allocator);
    defer std.testing.allocator.free(target_did);

    const open = try mesh_api.openRelayRoute(
        &relay_server,
        501,
        source.public_key,
        source_did,
        target.public_key,
        target_did,
    );
    try std.testing.expect(open.session.authenticated);
}
