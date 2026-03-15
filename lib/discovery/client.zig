const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const protocol = @import("protocol.zig");

pub fn buildLookup(allocator: std.mem.Allocator, correlation_id: u64, node_id: libself.NodeId) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .lookup,
        .correlation_id = correlation_id,
        .node_hex = &node_id.toHex(),
        .payload = "",
    });
}

pub fn buildWithdraw(allocator: std.mem.Allocator, correlation_id: u64, node_id: libself.NodeId) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .withdraw,
        .correlation_id = correlation_id,
        .node_hex = &node_id.toHex(),
        .payload = "",
    });
}

test "discovery client builds lookup message with node hex id" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd1} ** 32);
    const node_id = libself.NodeId.fromPublicKey(kp.public_key);
    const encoded = try buildLookup(std.testing.allocator, 1, node_id);
    defer std.testing.allocator.free(encoded);

    const decoded = try protocol.decode(encoded);
    try std.testing.expectEqual(protocol.MessageKind.lookup, decoded.kind);
    try std.testing.expectEqualStrings(&node_id.toHex(), decoded.node_hex);
}
