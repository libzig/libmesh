const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const max_payload_len: usize = 2048;

pub const MessageKind = enum {
    connect_request,
    connect_accept,
    connect_reject,
    candidate,
    setup_payload,

    fn asText(self: MessageKind) []const u8 {
        return switch (self) {
            .connect_request => "connect_request",
            .connect_accept => "connect_accept",
            .connect_reject => "connect_reject",
            .candidate => "candidate",
            .setup_payload => "setup_payload",
        };
    }

    fn fromText(text: []const u8) ?MessageKind {
        if (std.mem.eql(u8, text, "connect_request")) return .connect_request;
        if (std.mem.eql(u8, text, "connect_accept")) return .connect_accept;
        if (std.mem.eql(u8, text, "connect_reject")) return .connect_reject;
        if (std.mem.eql(u8, text, "candidate")) return .candidate;
        if (std.mem.eql(u8, text, "setup_payload")) return .setup_payload;
        return null;
    }
};

pub const Message = struct {
    kind: MessageKind,
    from_node: []const u8,
    to_node: []const u8,
    correlation_id: u64,
    payload: []const u8,
};

pub fn encode(allocator: std.mem.Allocator, msg: Message) MeshError![]u8 {
    if (msg.correlation_id == 0) return MeshError.InvalidPeerRecord;
    if (msg.payload.len > max_payload_len) return MeshError.BufferTooSmall;
    return std.fmt.allocPrint(allocator, "{s}|{s}|{s}|{d}|{s}", .{
        msg.kind.asText(),
        msg.from_node,
        msg.to_node,
        msg.correlation_id,
        msg.payload,
    }) catch MeshError.BufferTooSmall;
}

pub fn decode(raw: []const u8) MeshError!Message {
    var parts = std.mem.splitScalar(u8, raw, '|');
    const kind_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const from_node = parts.next() orelse return MeshError.InvalidPeerRecord;
    const to_node = parts.next() orelse return MeshError.InvalidPeerRecord;
    const correlation_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const payload = parts.next() orelse return MeshError.InvalidPeerRecord;
    if (parts.next() != null) return MeshError.InvalidPeerRecord;

    const kind = MessageKind.fromText(kind_text) orelse return MeshError.InvalidPeerRecord;
    const correlation_id = std.fmt.parseInt(u64, correlation_text, 10) catch return MeshError.InvalidPeerRecord;
    if (correlation_id == 0) return MeshError.InvalidPeerRecord;
    if (payload.len > max_payload_len) return MeshError.BufferTooSmall;

    return .{
        .kind = kind,
        .from_node = from_node,
        .to_node = to_node,
        .correlation_id = correlation_id,
        .payload = payload,
    };
}

test "signaling protocol encode/decode roundtrip" {
    const allocator = std.testing.allocator;
    const encoded = try encode(allocator, .{
        .kind = .candidate,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 7,
        .payload = "ice-candidate",
    });
    defer allocator.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(MessageKind.candidate, decoded.kind);
    try std.testing.expectEqual(@as(u64, 7), decoded.correlation_id);
    try std.testing.expectEqualStrings("ice-candidate", decoded.payload);
}

test "signaling protocol rejects malformed message" {
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("bad"));
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("connect_request|a|b|0|x"));
}
