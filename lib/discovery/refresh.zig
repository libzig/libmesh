const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const Store = @import("store.zig").InMemoryStore;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

pub fn run(store: *Store, record: PeerRecord, signer_public_key: libself.identity.PublicKey, now_ms: u64) MeshError!void {
    try store.refresh(record, signer_public_key, now_ms);
}

test "refresh.run updates existing record" {
    const std = @import("std");
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xc3} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.22", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-refresh", .relay_address = "relay.example.net:4433" },
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

    var updated = record;
    updated.expires_at_ms = 200;
    try updated.sign(std.testing.allocator, kp);
    try run(&store, updated, kp.public_key, 20);

    try std.testing.expectEqual(@as(u64, 200), (try store.lookup(updated.node_id)).expires_at_ms);
}
