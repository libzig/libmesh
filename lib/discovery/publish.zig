const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const Store = @import("store.zig").InMemoryStore;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

pub fn run(store: *Store, record: PeerRecord, signer_public_key: libself.identity.PublicKey, now_ms: u64) MeshError!void {
    try store.publish(record, signer_public_key, now_ms);
}

test "publish.run stores a verified peer record" {
    const std = @import("std");
    var store = Store.init(std.testing.allocator);
    defer store.deinit();

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xc1} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.20", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-pub", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try run(&store, record, kp.public_key, 10);
}
