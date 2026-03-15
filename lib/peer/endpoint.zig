const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const EndpointTransport = enum {
    quic,
};

pub const PublishedEndpoint = struct {
    host: []const u8,
    port: u16,
    priority: i16 = 0,
    transport: EndpointTransport = .quic,
    alpn: ?[]const u8 = null,

    pub fn validate(self: PublishedEndpoint) MeshError!void {
        if (self.host.len == 0) return MeshError.InvalidEndpoint;
        if (self.port == 0) return MeshError.InvalidEndpoint;
        if (std.mem.indexOfAny(u8, self.host, " \t\r\n") != null) return MeshError.InvalidEndpoint;
    }
};

test "PublishedEndpoint validates a proper QUIC hint" {
    const endpoint = PublishedEndpoint{
        .host = "203.0.113.8",
        .port = 4433,
        .priority = 10,
        .alpn = "mesh/1",
    };
    try endpoint.validate();
}

test "PublishedEndpoint rejects invalid values" {
    const bad_host = PublishedEndpoint{ .host = "", .port = 4433 };
    try std.testing.expectError(MeshError.InvalidEndpoint, bad_host.validate());

    const bad_port = PublishedEndpoint{ .host = "mesh.example", .port = 0 };
    try std.testing.expectError(MeshError.InvalidEndpoint, bad_port.validate());
}
