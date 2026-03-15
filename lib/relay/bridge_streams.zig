const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const RelaySession = @import("session.zig").RelaySession;

pub fn forward(
    allocator: std.mem.Allocator,
    session: RelaySession,
    sink: *std.ArrayList(u8),
    chunk: []const u8,
) MeshError!usize {
    if (!session.authenticated) return MeshError.AccessDenied;
    sink.appendSlice(allocator, chunk) catch return MeshError.BufferTooSmall;
    return chunk.len;
}

test "forward writes bytes when relay session is authenticated" {
    const key_pair = try @import("libself").identity.KeyPair.fromSeed([_]u8{0xa1} ** 32);
    const node_id = @import("libself").NodeId.fromPublicKey(key_pair.public_key);
    const session = RelaySession{
        .id = 7,
        .source_node_id = node_id,
        .target_node_id = @import("libself").NodeId.fromPublicKey((try @import("libself").identity.KeyPair.fromSeed([_]u8{0xa2} ** 32)).public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = true,
    };

    var sink = std.ArrayList(u8).empty;
    defer sink.deinit(std.testing.allocator);
    const written = try forward(std.testing.allocator, session, &sink, "stream-data");
    try std.testing.expectEqual(@as(usize, 11), written);
    try std.testing.expectEqualStrings("stream-data", sink.items);
}

test "forward rejects unauthenticated relay session" {
    const key_pair = try @import("libself").identity.KeyPair.fromSeed([_]u8{0xa3} ** 32);
    const session = RelaySession{
        .id = 8,
        .source_node_id = @import("libself").NodeId.fromPublicKey(key_pair.public_key),
        .target_node_id = @import("libself").NodeId.fromPublicKey((try @import("libself").identity.KeyPair.fromSeed([_]u8{0xa4} ** 32)).public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = false,
    };

    var sink = std.ArrayList(u8).empty;
    defer sink.deinit(std.testing.allocator);
    try std.testing.expectError(MeshError.AccessDenied, forward(std.testing.allocator, session, &sink, "x"));
}
