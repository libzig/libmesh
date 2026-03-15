const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

pub fn verifyRecord(
    allocator: std.mem.Allocator,
    record: PeerRecord,
    signer_public_key: libself.identity.PublicKey,
    now_ms: u64,
) MeshError!void {
    try record.validate(now_ms);
    const valid = record.verify(allocator, signer_public_key) catch return MeshError.BufferTooSmall;
    if (!valid) return MeshError.InvalidSignature;
}

test "verifyRecord accepts a valid signed peer record" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0xb2} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.12", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-verify", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);

    try verifyRecord(std.testing.allocator, record, key_pair.public_key, 20);
}

test "verifyRecord rejects wrong signer public key" {
    const signer = try libself.identity.KeyPair.fromSeed([_]u8{0xb3} ** 32);
    const other = try libself.identity.KeyPair.fromSeed([_]u8{0xb4} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.13", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-verify-2", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(signer.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, signer);

    try std.testing.expectError(MeshError.InvalidSignature, verifyRecord(std.testing.allocator, record, other.public_key, 20));
}
