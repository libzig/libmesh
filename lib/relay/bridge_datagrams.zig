const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const RelaySession = @import("session.zig").RelaySession;

pub const max_datagram_len: usize = 1200;

pub fn forward(
    allocator: std.mem.Allocator,
    session: RelaySession,
    datagram: []const u8,
) MeshError![]u8 {
    if (!session.authenticated) return MeshError.AccessDenied;
    if (datagram.len > max_datagram_len) return MeshError.BufferTooSmall;
    return allocator.dupe(u8, datagram) catch MeshError.BufferTooSmall;
}

test "datagram bridge forwards authenticated datagrams" {
    const libself = @import("libself");
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xe1} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xe2} ** 32);
    const session = RelaySession{
        .id = 1,
        .source_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = true,
    };

    const out = try forward(std.testing.allocator, session, "dg");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("dg", out);
}

test "datagram bridge rejects unauthenticated or oversized datagrams" {
    const libself = @import("libself");
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xe3} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xe4} ** 32);
    const unauth = RelaySession{
        .id = 2,
        .source_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = false,
    };
    try std.testing.expectError(MeshError.AccessDenied, forward(std.testing.allocator, unauth, "x"));

    const auth = RelaySession{
        .id = 3,
        .source_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = true,
    };
    var too_big: [max_datagram_len + 1]u8 = undefined;
    @memset(&too_big, 'z');
    try std.testing.expectError(MeshError.BufferTooSmall, forward(std.testing.allocator, auth, &too_big));
}
