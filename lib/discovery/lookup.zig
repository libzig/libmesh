const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const Store = @import("store.zig").InMemoryStore;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

pub fn run(store: *const Store, node_id: libself.NodeId) MeshError!PeerRecord {
    return store.lookup(node_id);
}

test "lookup.run returns stored peer record" {
    const std = @import("std");
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xc2} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.21", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-lookup", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try store.publish(record, kp.public_key, 10);

    const loaded = try run(&store, record.node_id);
    try std.testing.expectEqual(record.expires_at_ms, loaded.expires_at_ms);
}
