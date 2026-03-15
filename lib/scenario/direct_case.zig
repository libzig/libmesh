const std = @import("std");
const libself = @import("libself");
const mesh_api = @import("../mesh.zig");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

fn resolvedFromRecord(record: @import("../peer/peer_record.zig").PeerRecord) ResolvedPeer {
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{};
    return .{
        .record = record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "scenario case A resolves a direct route and skips relay" {
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0xa1} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.200", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{};
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 100,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try mesh_api.publishSelf(&store, key_pair.public_key, record, 110);

    const loaded = try mesh_api.lookupPeer(&store, key_pair.public_key, record.node_id);
    const resolved = resolvedFromRecord(loaded);
    const plan = try mesh_api.resolveRoutes(std.testing.allocator, resolved, .{});
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("../routing/policy.zig").Decision.direct, plan.decision);
    try std.testing.expectEqual(@as(usize, 1), plan.targets.len);
    switch (plan.targets[0]) {
        .direct => {},
        else => return error.TestUnexpectedResult,
    }
}
