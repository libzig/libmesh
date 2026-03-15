const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const MessageKind = enum {
    publish,
    lookup,
    refresh,
    withdraw,
    response,

    fn asText(self: MessageKind) []const u8 {
        return switch (self) {
            .publish => "publish",
            .lookup => "lookup",
            .refresh => "refresh",
            .withdraw => "withdraw",
            .response => "response",
        };
    }

    fn fromText(text: []const u8) ?MessageKind {
        if (std.mem.eql(u8, text, "publish")) return .publish;
        if (std.mem.eql(u8, text, "lookup")) return .lookup;
        if (std.mem.eql(u8, text, "refresh")) return .refresh;
        if (std.mem.eql(u8, text, "withdraw")) return .withdraw;
        if (std.mem.eql(u8, text, "response")) return .response;
        return null;
    }
};

pub const Message = struct {
    kind: MessageKind,
    correlation_id: u64,
    node_hex: []const u8,
    payload: []const u8,
};

pub fn encode(allocator: std.mem.Allocator, msg: Message) MeshError![]u8 {
    if (msg.correlation_id == 0) return MeshError.InvalidPeerRecord;
    if (std.mem.indexOfScalar(u8, msg.node_hex, '|') != null) return MeshError.InvalidPeerRecord;
    if (std.mem.indexOfScalar(u8, msg.payload, '|') != null) return MeshError.InvalidPeerRecord;
    return std.fmt.allocPrint(allocator, "{s}|{d}|{s}|{s}", .{
        msg.kind.asText(),
        msg.correlation_id,
        msg.node_hex,
        msg.payload,
    }) catch MeshError.BufferTooSmall;
}

pub fn decode(raw: []const u8) MeshError!Message {
    var parts = std.mem.splitScalar(u8, raw, '|');
    const kind_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const correlation_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const node_hex = parts.next() orelse return MeshError.InvalidPeerRecord;
    const payload = parts.next() orelse return MeshError.InvalidPeerRecord;
    if (parts.next() != null) return MeshError.InvalidPeerRecord;

    const kind = MessageKind.fromText(kind_text) orelse return MeshError.InvalidPeerRecord;
    const correlation_id = std.fmt.parseInt(u64, correlation_text, 10) catch return MeshError.InvalidPeerRecord;
    if (correlation_id == 0) return MeshError.InvalidPeerRecord;

    return .{
        .kind = kind,
        .correlation_id = correlation_id,
        .node_hex = node_hex,
        .payload = payload,
    };
}

test "discovery protocol encodes and decodes publish message" {
    const allocator = std.testing.allocator;
    const encoded = try encode(allocator, .{
        .kind = .publish,
        .correlation_id = 42,
        .node_hex = "abcd",
        .payload = "peer-record",
    });
    defer allocator.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(MessageKind.publish, decoded.kind);
    try std.testing.expectEqual(@as(u64, 42), decoded.correlation_id);
    try std.testing.expectEqualStrings("peer-record", decoded.payload);
}

test "discovery protocol rejects malformed data" {
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("bad"));
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("lookup|0|abcd|x"));
}

test "discovery protocol encode rejects delimiter in node or payload fields" {
    try std.testing.expectError(MeshError.InvalidPeerRecord, encode(std.testing.allocator, .{
        .kind = .lookup,
        .correlation_id = 1,
        .node_hex = "abc|def",
        .payload = "x",
    }));
    try std.testing.expectError(MeshError.InvalidPeerRecord, encode(std.testing.allocator, .{
        .kind = .lookup,
        .correlation_id = 1,
        .node_hex = "abcdef",
        .payload = "x|y",
    }));
}
