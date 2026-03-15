const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const Store = @import("store.zig").InMemoryStore;

pub fn run(store: *Store, node_id: libself.NodeId) MeshError!void {
    try store.withdraw(node_id);
}

test "withdraw.run removes previously stored record" {
    const std = @import("std");
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xc4} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.23", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-withdraw", .relay_address = "relay.example.net:4433" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try store.publish(record, kp.public_key, 10);

    try run(&store, record.node_id);
    try std.testing.expectError(MeshError.NotFound, store.lookup(record.node_id));
}
