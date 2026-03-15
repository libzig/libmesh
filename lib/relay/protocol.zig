const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const MessageKind = enum {
    open,
    accept,
    deny,
    stream_chunk,
    datagram,
    close,

    fn asText(self: MessageKind) []const u8 {
        return switch (self) {
            .open => "open",
            .accept => "accept",
            .deny => "deny",
            .stream_chunk => "stream_chunk",
            .datagram => "datagram",
            .close => "close",
        };
    }

    fn fromText(text: []const u8) ?MessageKind {
        if (std.mem.eql(u8, text, "open")) return .open;
        if (std.mem.eql(u8, text, "accept")) return .accept;
        if (std.mem.eql(u8, text, "deny")) return .deny;
        if (std.mem.eql(u8, text, "stream_chunk")) return .stream_chunk;
        if (std.mem.eql(u8, text, "datagram")) return .datagram;
        if (std.mem.eql(u8, text, "close")) return .close;
        return null;
    }
};

pub const Message = struct {
    kind: MessageKind,
    session_id: u64,
    payload: []const u8,
};

pub fn encode(allocator: std.mem.Allocator, msg: Message) MeshError![]u8 {
    if (msg.session_id == 0) return MeshError.InvalidPeerRecord;
    return std.fmt.allocPrint(allocator, "{s}|{d}|{s}", .{
        msg.kind.asText(),
        msg.session_id,
        msg.payload,
    }) catch MeshError.BufferTooSmall;
}

pub fn decode(raw: []const u8) MeshError!Message {
    var parts = std.mem.splitScalar(u8, raw, '|');
    const kind_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const session_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const payload = parts.next() orelse return MeshError.InvalidPeerRecord;
    if (parts.next() != null) return MeshError.InvalidPeerRecord;

    const kind = MessageKind.fromText(kind_text) orelse return MeshError.InvalidPeerRecord;
    const session_id = std.fmt.parseInt(u64, session_text, 10) catch return MeshError.InvalidPeerRecord;
    if (session_id == 0) return MeshError.InvalidPeerRecord;

    return .{
        .kind = kind,
        .session_id = session_id,
        .payload = payload,
    };
}

test "relay protocol encode/decode roundtrip for datagram message" {
    const allocator = std.testing.allocator;
    const encoded = try encode(allocator, .{
        .kind = .datagram,
        .session_id = 9,
        .payload = "hello",
    });
    defer allocator.free(encoded);

    const decoded = try decode(encoded);
    try std.testing.expectEqual(MessageKind.datagram, decoded.kind);
    try std.testing.expectEqual(@as(u64, 9), decoded.session_id);
    try std.testing.expectEqualStrings("hello", decoded.payload);
}

test "relay protocol rejects malformed records" {
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("bad"));
    try std.testing.expectError(MeshError.InvalidPeerRecord, decode("open|0|x"));
}
