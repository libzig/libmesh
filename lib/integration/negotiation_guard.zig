const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const version = @import("../common/version.zig");
const caps = @import("../common/caps.zig");
const control = @import("control_session.zig");

pub const LocalConfig = struct {
    version: version.ProtocolVersion = version.current,
    capabilities: caps.Capabilities = .{},
};

pub fn validate(local: LocalConfig, remote: control.Envelope) MeshError!control.Negotiated {
    return control.negotiate(local.version, local.capabilities, remote);
}

pub fn requireCapability(negotiated: control.Negotiated, capability: enum {
    discovery,
    signaling,
    relay_stream,
    relay_datagram,
}) MeshError!void {
    const ok = switch (capability) {
        .discovery => negotiated.capabilities.discovery,
        .signaling => negotiated.capabilities.signaling,
        .relay_stream => negotiated.capabilities.relay_stream,
        .relay_datagram => negotiated.capabilities.relay_datagram,
    };
    if (!ok) return MeshError.AccessDenied;
}

test "negotiation guard validates compatible control envelope" {
    const negotiated = try validate(.{
        .version = .{ .major = 1, .minor = 2, .patch = 0 },
        .capabilities = .{
            .discovery = true,
            .signaling = true,
        },
    }, .{
        .kind = .request,
        .correlation_id = 1,
        .version = .{ .major = 1, .minor = 1, .patch = 5 },
        .capabilities = .{
            .discovery = true,
            .signaling = false,
        },
        .payload = "x",
    });
    try std.testing.expectEqual(@as(u16, 1), negotiated.version.minor);
    try requireCapability(negotiated, .discovery);
    try std.testing.expectError(MeshError.AccessDenied, requireCapability(negotiated, .signaling));
}

test "negotiation guard rejects incompatible major versions" {
    try std.testing.expectError(MeshError.InvalidVersion, validate(.{
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{},
    }, .{
        .kind = .request,
        .correlation_id = 1,
        .version = .{ .major = 2, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = "x",
    }));
}
