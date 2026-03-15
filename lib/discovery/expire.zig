const std = @import("std");
const Store = @import("store.zig").InMemoryStore;

pub fn run(store: *Store, now_ms: u64) usize {
    return store.pruneExpired(now_ms);
}

test "expire.run prunes stale records and returns removed count" {
    const libself = @import("libself");
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xc5} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.24", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-expire", .relay_address = "relay.example.net:4433" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 10,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try store.publish(record, kp.public_key, 2);

    try std.testing.expectEqual(@as(usize, 1), run(&store, 99));
    try std.testing.expectEqual(@as(usize, 0), run(&store, 99));
}
