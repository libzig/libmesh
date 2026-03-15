const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const guard = @import("../integration/negotiation_guard.zig");
const control = @import("../integration/control_session.zig");
const Endpoint = @import("../integration/session_endpoint.zig").Endpoint;
const request_exchange = @import("../integration/request_exchange.zig");
const retry = @import("../integration/retry.zig");
const protocol = @import("protocol.zig");

pub const SessionTransport = struct {
    client_id: []const u8,
    server_id: []const u8,
    client: Endpoint,
    server: Endpoint,

    pub fn send(self: SessionTransport, allocator: std.mem.Allocator, message: protocol.Message) MeshError!void {
        const payload = try protocol.encode(allocator, message);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = message.session_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{
                .relay_stream = true,
                .relay_datagram = true,
            },
            .payload = payload,
        });
    }

    pub fn pumpServer(self: SessionTransport, allocator: std.mem.Allocator, allow_open: bool) MeshError!bool {
        const incoming = (try self.server.recvEnvelope(allocator)) orelse return false;
        defer incoming.deinit(allocator);
        if (incoming.envelope.kind != .request) return MeshError.InvalidPeerRecord;
        const negotiated = try guard.validate(.{
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{
                .relay_stream = true,
                .relay_datagram = true,
            },
        }, incoming.envelope);
        try guard.requireCapability(negotiated, .relay_stream);
        const request = try protocol.decode(incoming.envelope.payload);

        const response_payload = try protocol.encode(allocator, switch (request.kind) {
            .open => .{
                .kind = if (allow_open) .accept else .deny,
                .session_id = request.session_id,
                .payload = if (allow_open) "open-ok" else "open-denied",
            },
            .close => .{
                .kind = .accept,
                .session_id = request.session_id,
                .payload = "closed",
            },
            else => .{
                .kind = .accept,
                .session_id = request.session_id,
                .payload = "forwarded",
            },
        });
        defer allocator.free(response_payload);

        try self.server.sendEnvelope(allocator, self.client_id, .{
            .kind = .response,
            .correlation_id = request.session_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .relay_stream = true },
            .payload = response_payload,
        });
        return true;
    }

    pub fn recv(self: SessionTransport, allocator: std.mem.Allocator, session_id: u64) MeshError!protocol.Message {
        const response = try self.client.expectResponse(allocator, session_id);
        defer response.deinit(allocator);
        return protocol.decode(response.envelope.payload);
    }

    const PumpContext = struct {
        transport: *const SessionTransport,
        allow_open: bool,
    };

    fn pumpAdapter(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) MeshError!bool {
        const ctx: *PumpContext = @ptrCast(@alignCast(ctx_ptr));
        return ctx.transport.pumpServer(allocator, ctx.allow_open);
    }

    pub fn roundTrip(
        self: SessionTransport,
        allocator: std.mem.Allocator,
        message: protocol.Message,
        policy: retry.Policy,
        allow_open: bool,
    ) MeshError!protocol.Message {
        const payload = try protocol.encode(allocator, message);
        defer allocator.free(payload);
        var pump_ctx = PumpContext{
            .transport = &self,
            .allow_open = allow_open,
        };
        var validate_ctx: u8 = 0;
        const response = try request_exchange.requestResponseValidated(
            allocator,
            self.client,
            self.server_id,
            .{
                .kind = .request,
                .correlation_id = message.session_id,
                .version = .{ .major = 1, .minor = 0, .patch = 0 },
                .capabilities = .{ .relay_stream = true },
                .payload = payload,
            },
            policy,
            &pump_ctx,
            pumpAdapter,
            &validate_ctx,
            validateRoundTripResponse,
        );
        defer response.deinit(allocator);
        return protocol.decode(response.envelope.payload);
    }

    fn validateRoundTripResponse(_: *anyopaque, response: control.Envelope) MeshError!void {
        const parsed = protocol.decode(response.payload) catch return MeshError.NotFound;
        if (parsed.kind != .accept and parsed.kind != .deny) return MeshError.NotFound;
    }
};

test "relay session transport open request receives accept response" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    try transport.send(std.testing.allocator, .{
        .kind = .open,
        .session_id = 900,
        .payload = "node-b",
    });
    try std.testing.expect(try transport.pumpServer(std.testing.allocator, true));
    const response = try transport.recv(std.testing.allocator, 900);
    try std.testing.expectEqual(protocol.MessageKind.accept, response.kind);
}

test "relay session transport open can be denied by server policy" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    try transport.send(std.testing.allocator, .{
        .kind = .open,
        .session_id = 901,
        .payload = "node-b",
    });
    try std.testing.expect(try transport.pumpServer(std.testing.allocator, false));
    const response = try transport.recv(std.testing.allocator, 901);
    try std.testing.expectEqual(protocol.MessageKind.deny, response.kind);
}

test "relay session transport rejects incompatible major versions" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };
    const payload = try protocol.encode(std.testing.allocator, .{
        .kind = .open,
        .session_id = 902,
        .payload = "node-b",
    });
    defer std.testing.allocator.free(payload);

    try transport.client.sendEnvelope(std.testing.allocator, "mesh-relay", .{
        .kind = .request,
        .correlation_id = 902,
        .version = .{ .major = 2, .minor = 0, .patch = 0 },
        .capabilities = .{ .relay_stream = true },
        .payload = payload,
    });
    try std.testing.expectError(MeshError.InvalidVersion, transport.pumpServer(std.testing.allocator, true));
}

test "relay session transport rejects missing relay stream capability" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };
    const payload = try protocol.encode(std.testing.allocator, .{
        .kind = .open,
        .session_id = 903,
        .payload = "node-b",
    });
    defer std.testing.allocator.free(payload);

    try transport.client.sendEnvelope(std.testing.allocator, "mesh-relay", .{
        .kind = .request,
        .correlation_id = 903,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = payload,
    });
    try std.testing.expectError(MeshError.AccessDenied, transport.pumpServer(std.testing.allocator, true));
}

test "relay session transport roundTrip helper returns accept and deny outcomes" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    const accept = try transport.roundTrip(std.testing.allocator, .{
        .kind = .open,
        .session_id = 910,
        .payload = "node-b",
    }, .{ .max_attempts = 2 }, true);
    try std.testing.expectEqual(protocol.MessageKind.accept, accept.kind);

    const deny = try transport.roundTrip(std.testing.allocator, .{
        .kind = .open,
        .session_id = 911,
        .payload = "node-b",
    }, .{ .max_attempts = 2 }, false);
    try std.testing.expectEqual(protocol.MessageKind.deny, deny.kind);
}

test "relay session transport roundTrip retries on invalid first response payload" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    try transport.server.sendResponse(std.testing.allocator, "node-a", 912, .{ .relay_stream = true }, "bad");
    const recovered = try transport.roundTrip(std.testing.allocator, .{
        .kind = .open,
        .session_id = 912,
        .payload = "node-b",
    }, .{ .max_attempts = 3 }, true);
    try std.testing.expectEqual(protocol.MessageKind.accept, recovered.kind);
}
