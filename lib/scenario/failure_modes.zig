const std = @import("std");
const libself = @import("libself");
const mesh_api = @import("../mesh.zig");
const MeshError = @import("../common/error.zig").MeshError;

test "scenario failure mode: stale discovery record is rejected at lookup time" {
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0xa5} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.203", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-fail-stale", .relay_address = "relay.example.net:9443" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 20,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try mesh_api.publishSelf(&store, key_pair.public_key, record, 11);
    try std.testing.expectError(
        MeshError.Expired,
        mesh_api.lookupPeerAt(&store, key_pair.public_key, record.node_id, 30),
    );
}

test "scenario failure mode: relay open rejects did/public-key mismatch" {
    var matcher = @import("../relay/matcher.zig").Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var relay_server = @import("../relay/server.zig").Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 4,
        .require_authenticated = true,
    });
    defer relay_server.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xa6} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xa7} ** 32);
    const source_did = try libself.DidKey.fromKeyPair(source).encode(std.testing.allocator);
    defer std.testing.allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(std.testing.allocator);
    defer std.testing.allocator.free(target_did);

    try std.testing.expectError(
        MeshError.AccessDenied,
        mesh_api.openRelayRoute(
            &relay_server,
            601,
            source.public_key,
            source_did,
            target.public_key,
            source_did,
        ),
    );
}
