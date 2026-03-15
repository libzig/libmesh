const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const protocol = @import("protocol.zig");

pub fn buildOpen(allocator: std.mem.Allocator, session_id: u64, target_node: []const u8) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .open,
        .session_id = session_id,
        .payload = target_node,
    });
}

pub fn buildClose(allocator: std.mem.Allocator, session_id: u64) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .close,
        .session_id = session_id,
        .payload = "",
    });
}

pub fn decodeOpenResult(raw: []const u8) MeshError!protocol.Message {
    const msg = try protocol.decode(raw);
    return switch (msg.kind) {
        .accept, .deny => msg,
        else => MeshError.InvalidPeerRecord,
    };
}

pub fn decodeOpenResultForSession(raw: []const u8, expected_session_id: u64) MeshError!protocol.Message {
    const msg = try decodeOpenResult(raw);
    if (msg.session_id != expected_session_id) return MeshError.InvalidPeerRecord;
    return msg;
}

test "relay client builds open and close messages" {
    const allocator = std.testing.allocator;
    const open_raw = try buildOpen(allocator, 41, "target-node");
    defer allocator.free(open_raw);
    const open_msg = try protocol.decode(open_raw);
    try std.testing.expectEqual(protocol.MessageKind.open, open_msg.kind);
    try std.testing.expectEqualStrings("target-node", open_msg.payload);

    const close_raw = try buildClose(allocator, 41);
    defer allocator.free(close_raw);
    const close_msg = try protocol.decode(close_raw);
    try std.testing.expectEqual(protocol.MessageKind.close, close_msg.kind);
}

test "relay client decodeOpenResult accepts only accept/deny" {
    const allocator = std.testing.allocator;
    const accept_raw = try protocol.encode(allocator, .{
        .kind = .accept,
        .session_id = 9,
        .payload = "ok",
    });
    defer allocator.free(accept_raw);
    const accept = try decodeOpenResult(accept_raw);
    try std.testing.expectEqual(protocol.MessageKind.accept, accept.kind);

    const open_raw = try protocol.encode(allocator, .{
        .kind = .open,
        .session_id = 9,
        .payload = "x",
    });
    defer allocator.free(open_raw);
    try std.testing.expectError(MeshError.InvalidPeerRecord, decodeOpenResult(open_raw));
}

test "relay client decodeOpenResultForSession validates expected session id" {
    const allocator = std.testing.allocator;
    const accept_raw = try protocol.encode(allocator, .{
        .kind = .accept,
        .session_id = 42,
        .payload = "ok",
    });
    defer allocator.free(accept_raw);

    const accepted = try decodeOpenResultForSession(accept_raw, 42);
    try std.testing.expectEqual(protocol.MessageKind.accept, accepted.kind);
    try std.testing.expectError(MeshError.InvalidPeerRecord, decodeOpenResultForSession(accept_raw, 43));
}
