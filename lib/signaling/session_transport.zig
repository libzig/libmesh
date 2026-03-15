const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const guard = @import("../integration/negotiation_guard.zig");
const Endpoint = @import("../integration/session_endpoint.zig").Endpoint;
const request_exchange = @import("../integration/request_exchange.zig");
const retry = @import("../integration/retry.zig");
const protocol = @import("protocol.zig");
const Exchange = @import("exchange.zig").Exchange;
const Rendezvous = @import("rendezvous.zig").Rendezvous;
const Server = @import("server.zig").Server;

pub const SessionTransport = struct {
    client_id: []const u8,
    server_id: []const u8,
    client: Endpoint,
    server: Endpoint,
    exchange: *Exchange,
    rendezvous: *Rendezvous,

    pub fn send(self: SessionTransport, allocator: std.mem.Allocator, message: protocol.Message) MeshError!void {
        const payload = try protocol.encode(allocator, message);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = message.correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .signaling = true },
            .payload = payload,
        });
    }

    pub fn pumpServer(self: SessionTransport, allocator: std.mem.Allocator) MeshError!bool {
        const incoming = (try self.server.recvEnvelope(allocator)) orelse return false;
        defer incoming.deinit(allocator);
        if (incoming.envelope.kind != .request) return MeshError.InvalidPeerRecord;
        const negotiated = try guard.validate(.{
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .signaling = true },
        }, incoming.envelope);
        try guard.requireCapability(negotiated, .signaling);

        const message = try protocol.decode(incoming.envelope.payload);
        try self.exchange.send(message.from_node, message.to_node, message);
        const worker = Server{
            .exchange = self.exchange,
            .rendezvous = self.rendezvous,
            .local_node = message.to_node,
        };
        _ = try worker.processNext();

        try self.server.sendEnvelope(allocator, self.client_id, .{
            .kind = .response,
            .correlation_id = message.correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .signaling = true },
            .payload = "ok",
        });
        return true;
    }

    pub fn recvAck(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64) MeshError!void {
        const response = try self.client.expectResponse(allocator, correlation_id);
        defer response.deinit(allocator);
        if (!std.mem.eql(u8, response.envelope.payload, "ok")) return MeshError.InvalidPeerRecord;
    }

    fn pumpAdapter(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) MeshError!bool {
        const self: *const SessionTransport = @ptrCast(@alignCast(ctx_ptr));
        return self.pumpServer(allocator);
    }

    pub fn roundTrip(self: SessionTransport, allocator: std.mem.Allocator, message: protocol.Message, policy: retry.Policy) MeshError!void {
        const payload = try protocol.encode(allocator, message);
        defer allocator.free(payload);
        const response = try request_exchange.requestResponse(
            allocator,
            self.client,
            self.server_id,
            .{
                .kind = .request,
                .correlation_id = message.correlation_id,
                .version = .{ .major = 1, .minor = 0, .patch = 0 },
                .capabilities = .{ .signaling = true },
                .payload = payload,
            },
            policy,
            @constCast(&self),
            pumpAdapter,
        );
        defer response.deinit(allocator);
        if (!std.mem.eql(u8, response.envelope.payload, "ok")) return MeshError.InvalidPeerRecord;
    }
};

test "signaling session transport processes request and updates rendezvous" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };

    try transport.send(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 77,
        .payload = "",
    });
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 77);
    try std.testing.expect(!rendezvous.isAccepted(77));

    try transport.send(std.testing.allocator, .{
        .kind = .connect_accept,
        .from_node = "node-b",
        .to_node = "node-a",
        .correlation_id = 77,
        .payload = "",
    });
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 77);
    try std.testing.expect(rendezvous.isAccepted(77));
}

test "signaling session transport rejects mismatched major versions" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    const payload = try protocol.encode(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 79,
        .payload = "",
    });
    defer std.testing.allocator.free(payload);

    try transport.client.sendEnvelope(std.testing.allocator, "mesh-signal", .{
        .kind = .request,
        .correlation_id = 79,
        .version = .{ .major = 2, .minor = 0, .patch = 0 },
        .capabilities = .{ .signaling = true },
        .payload = payload,
    });
    try std.testing.expectError(MeshError.InvalidVersion, transport.pumpServer(std.testing.allocator));
}

test "signaling session transport rejects missing signaling capability" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    const payload = try protocol.encode(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 80,
        .payload = "",
    });
    defer std.testing.allocator.free(payload);

    try transport.client.sendEnvelope(std.testing.allocator, "mesh-signal", .{
        .kind = .request,
        .correlation_id = 80,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = payload,
    });
    try std.testing.expectError(MeshError.AccessDenied, transport.pumpServer(std.testing.allocator));
}

test "signaling session transport roundTrip helper drives rendezvous state" {
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const transport = SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    try transport.roundTrip(std.testing.allocator, .{
        .kind = .connect_request,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 120,
        .payload = "",
    }, .{ .max_attempts = 2 });
    try std.testing.expect(!rendezvous.isAccepted(120));

    try transport.roundTrip(std.testing.allocator, .{
        .kind = .connect_accept,
        .from_node = "node-b",
        .to_node = "node-a",
        .correlation_id = 120,
        .payload = "",
    }, .{ .max_attempts = 2 });
    try std.testing.expect(rendezvous.isAccepted(120));
}
