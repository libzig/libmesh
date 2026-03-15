const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const ProtocolVersion = @import("../common/version.zig").ProtocolVersion;
const Capabilities = @import("../common/caps.zig").Capabilities;

pub const Kind = enum {
    request,
    response,

    fn asText(self: Kind) []const u8 {
        return switch (self) {
            .request => "request",
            .response => "response",
        };
    }

    fn fromText(text: []const u8) ?Kind {
        if (std.mem.eql(u8, text, "request")) return .request;
        if (std.mem.eql(u8, text, "response")) return .response;
        return null;
    }
};

pub const Envelope = struct {
    kind: Kind,
    correlation_id: u64,
    version: ProtocolVersion,
    capabilities: Capabilities,
    payload: []const u8,
};

pub const Negotiated = struct {
    version: ProtocolVersion,
    capabilities: Capabilities,
};

pub fn encode(allocator: std.mem.Allocator, envelope: Envelope) MeshError![]u8 {
    if (envelope.correlation_id == 0) return MeshError.InvalidPeerRecord;
    return std.fmt.allocPrint(allocator, "{s}|{d}|{d}.{d}.{d}|{d}{d}{d}{d}|{s}", .{
        envelope.kind.asText(),
        envelope.correlation_id,
        envelope.version.major,
        envelope.version.minor,
        envelope.version.patch,
        @intFromBool(envelope.capabilities.discovery),
        @intFromBool(envelope.capabilities.signaling),
        @intFromBool(envelope.capabilities.relay_stream),
        @intFromBool(envelope.capabilities.relay_datagram),
        envelope.payload,
    }) catch MeshError.BufferTooSmall;
}

pub fn decode(raw: []const u8) MeshError!Envelope {
    var parts = std.mem.splitScalar(u8, raw, '|');
    const kind_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const corr_text = parts.next() orelse return MeshError.InvalidPeerRecord;
    const version_text = parts.next() orelse return MeshError.InvalidVersion;
    const caps_text = parts.next() orelse return MeshError.InvalidVersion;
    const payload = parts.next() orelse return MeshError.InvalidPeerRecord;
    if (parts.next() != null) return MeshError.InvalidPeerRecord;

    const kind = Kind.fromText(kind_text) orelse return MeshError.InvalidPeerRecord;
    const correlation_id = std.fmt.parseInt(u64, corr_text, 10) catch return MeshError.InvalidPeerRecord;
    if (correlation_id == 0) return MeshError.InvalidPeerRecord;

    var semver = std.mem.splitScalar(u8, version_text, '.');
    const major_text = semver.next() orelse return MeshError.InvalidVersion;
    const minor_text = semver.next() orelse return MeshError.InvalidVersion;
    const patch_text = semver.next() orelse return MeshError.InvalidVersion;
    if (semver.next() != null) return MeshError.InvalidVersion;
    const major = std.fmt.parseInt(u16, major_text, 10) catch return MeshError.InvalidVersion;
    const minor = std.fmt.parseInt(u16, minor_text, 10) catch return MeshError.InvalidVersion;
    const patch = std.fmt.parseInt(u16, patch_text, 10) catch return MeshError.InvalidVersion;

    if (caps_text.len != 4) return MeshError.InvalidVersion;
    for (caps_text) |c| {
        if (c != '0' and c != '1') return MeshError.InvalidVersion;
    }

    return .{
        .kind = kind,
        .correlation_id = correlation_id,
        .version = .{
            .major = major,
            .minor = minor,
            .patch = patch,
        },
        .capabilities = .{
            .discovery = caps_text[0] == '1',
            .signaling = caps_text[1] == '1',
            .relay_stream = caps_text[2] == '1',
            .relay_datagram = caps_text[3] == '1',
        },
        .payload = payload,
    };
}

pub fn negotiate(
    local_version: ProtocolVersion,
    local_capabilities: Capabilities,
    remote: Envelope,
) MeshError!Negotiated {
    if (local_version.major != remote.version.major) return MeshError.InvalidVersion;

    return .{
        .version = .{
            .major = local_version.major,
            .minor = @min(local_version.minor, remote.version.minor),
            .patch = @min(local_version.patch, remote.version.patch),
        },
        .capabilities = .{
            .discovery = local_capabilities.discovery and remote.capabilities.discovery,
            .signaling = local_capabilities.signaling and remote.capabilities.signaling,
            .relay_stream = local_capabilities.relay_stream and remote.capabilities.relay_stream,
            .relay_datagram = local_capabilities.relay_datagram and remote.capabilities.relay_datagram,
        },
    };
}

test "control session encodes and decodes envelopes" {
    const allocator = std.testing.allocator;
    const raw = try encode(allocator, .{
        .kind = .request,
        .correlation_id = 7,
        .version = .{ .major = 1, .minor = 2, .patch = 3 },
        .capabilities = .{
            .discovery = true,
            .signaling = true,
            .relay_stream = true,
            .relay_datagram = false,
        },
        .payload = "lookup",
    });
    defer allocator.free(raw);

    const parsed = try decode(raw);
    try std.testing.expectEqual(Kind.request, parsed.kind);
    try std.testing.expectEqual(@as(u64, 7), parsed.correlation_id);
    try std.testing.expect(parsed.capabilities.discovery);
    try std.testing.expectEqualStrings("lookup", parsed.payload);
}

test "control session negotiation intersects capabilities and chooses compatible version" {
    const local_version = ProtocolVersion{ .major = 1, .minor = 4, .patch = 2 };
    const local_caps = Capabilities{
        .discovery = true,
        .signaling = true,
        .relay_stream = false,
        .relay_datagram = true,
    };
    const remote = Envelope{
        .kind = .response,
        .correlation_id = 9,
        .version = .{ .major = 1, .minor = 3, .patch = 7 },
        .capabilities = .{
            .discovery = true,
            .signaling = false,
            .relay_stream = true,
            .relay_datagram = true,
        },
        .payload = "ok",
    };

    const negotiated = try negotiate(local_version, local_caps, remote);
    try std.testing.expectEqual(@as(u16, 3), negotiated.version.minor);
    try std.testing.expect(negotiated.capabilities.discovery);
    try std.testing.expect(!negotiated.capabilities.signaling);
    try std.testing.expect(!negotiated.capabilities.relay_stream);
    try std.testing.expect(negotiated.capabilities.relay_datagram);
}

test "control session negotiation rejects incompatible major versions" {
    const local_version = ProtocolVersion{ .major = 1, .minor = 0, .patch = 0 };
    const remote = Envelope{
        .kind = .response,
        .correlation_id = 1,
        .version = .{ .major = 2, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = "ok",
    };
    try std.testing.expectError(MeshError.InvalidVersion, negotiate(local_version, .{}, remote));
}
