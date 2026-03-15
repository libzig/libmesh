const std = @import("std");
const libself = @import("libself");
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

pub fn signRecord(allocator: std.mem.Allocator, record: *PeerRecord, key_pair: libself.identity.KeyPair) !void {
    try record.sign(allocator, key_pair);
}

test "signRecord signs canonical peer record payload with libself key" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0xb1} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.11", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-sign", .relay_address = "relay.example.net:4433" },
    };

    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 200,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try signRecord(std.testing.allocator, &record, key_pair);

    try std.testing.expect(record.signature != null);
    try std.testing.expect(try record.verify(std.testing.allocator, key_pair.public_key));
}
