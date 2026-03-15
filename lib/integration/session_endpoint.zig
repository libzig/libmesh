const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const Capabilities = @import("../common/caps.zig").Capabilities;
const control = @import("control_session.zig");
const SessionBus = @import("session_bus.zig").SessionBus;

pub const OwnedEnvelope = struct {
    envelope: control.Envelope,
    payload_storage: []u8,

    pub fn deinit(self: OwnedEnvelope, allocator: std.mem.Allocator) void {
        allocator.free(self.payload_storage);
    }
};

pub const Endpoint = struct {
    id: []const u8,
    bus: *SessionBus,

    pub fn sendEnvelope(self: Endpoint, allocator: std.mem.Allocator, to: []const u8, env: control.Envelope) MeshError!void {
        const payload_hex = std.fmt.allocPrint(allocator, "{x}", .{env.payload}) catch return MeshError.BufferTooSmall;
        defer allocator.free(payload_hex);

        var wrapped = env;
        wrapped.payload = payload_hex;
        const encoded = try control.encode(allocator, wrapped);
        defer allocator.free(encoded);
        try self.bus.send(self.id, to, encoded);
    }

    pub fn sendRequest(
        self: Endpoint,
        allocator: std.mem.Allocator,
        to: []const u8,
        correlation_id: u64,
        capabilities: Capabilities,
        payload: []const u8,
    ) MeshError!void {
        try self.sendEnvelope(allocator, to, .{
            .kind = .request,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = capabilities,
            .payload = payload,
        });
    }

    pub fn sendResponse(
        self: Endpoint,
        allocator: std.mem.Allocator,
        to: []const u8,
        correlation_id: u64,
        capabilities: Capabilities,
        payload: []const u8,
    ) MeshError!void {
        try self.sendEnvelope(allocator, to, .{
            .kind = .response,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = capabilities,
            .payload = payload,
        });
    }

    pub fn recvEnvelope(self: Endpoint, allocator: std.mem.Allocator) MeshError!?OwnedEnvelope {
        const packet = self.bus.recv(self.id) orelse return null;
        defer {
            allocator.free(packet.from);
            allocator.free(packet.to);
            allocator.free(packet.payload);
        }
        const decoded = try control.decode(packet.payload);
        if (decoded.payload.len % 2 != 0) return MeshError.InvalidPeerRecord;
        const payload_storage = allocator.alloc(u8, decoded.payload.len / 2) catch return MeshError.BufferTooSmall;
        _ = std.fmt.hexToBytes(payload_storage, decoded.payload) catch return MeshError.InvalidPeerRecord;
        var envelope = decoded;
        envelope.payload = payload_storage;
        return .{
            .envelope = envelope,
            .payload_storage = payload_storage,
        };
    }

    pub fn expectResponse(self: Endpoint, allocator: std.mem.Allocator, correlation_id: u64) MeshError!OwnedEnvelope {
        const owned = (try self.recvEnvelope(allocator)) orelse return MeshError.NotFound;
        if (owned.envelope.kind != .response) {
            owned.deinit(allocator);
            return MeshError.InvalidPeerRecord;
        }
        if (owned.envelope.correlation_id != correlation_id) {
            owned.deinit(allocator);
            return MeshError.InvalidPeerRecord;
        }
        return owned;
    }

    pub fn expectResponseFrom(
        self: Endpoint,
        allocator: std.mem.Allocator,
        from: []const u8,
        correlation_id: u64,
    ) MeshError!OwnedEnvelope {
        const packet = self.bus.recvFrom(self.id, from) orelse return MeshError.NotFound;
        defer {
            allocator.free(packet.from);
            allocator.free(packet.to);
            allocator.free(packet.payload);
        }
        const decoded = try control.decode(packet.payload);
        if (decoded.payload.len % 2 != 0) return MeshError.InvalidPeerRecord;
        const payload_storage = allocator.alloc(u8, decoded.payload.len / 2) catch return MeshError.BufferTooSmall;
        errdefer allocator.free(payload_storage);
        _ = std.fmt.hexToBytes(payload_storage, decoded.payload) catch return MeshError.InvalidPeerRecord;
        if (decoded.kind != .response or decoded.correlation_id != correlation_id) return MeshError.InvalidPeerRecord;

        var envelope = decoded;
        envelope.payload = payload_storage;
        return .{
            .envelope = envelope,
            .payload_storage = payload_storage,
        };
    }
};

test "session endpoint sends and receives control envelopes over bus" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    const a = Endpoint{ .id = "node-a", .bus = &bus };
    const b = Endpoint{ .id = "node-b", .bus = &bus };

    try a.sendEnvelope(std.testing.allocator, "node-b", .{
        .kind = .request,
        .correlation_id = 1,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{ .discovery = true },
        .payload = "lookup",
    });
    const request = (try b.recvEnvelope(std.testing.allocator)).?;
    defer request.deinit(std.testing.allocator);
    try std.testing.expectEqual(control.Kind.request, request.envelope.kind);
    try std.testing.expectEqualStrings("lookup", request.envelope.payload);
}

test "session endpoint expectResponse validates correlation id" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    const a = Endpoint{ .id = "node-a", .bus = &bus };
    const b = Endpoint{ .id = "node-b", .bus = &bus };
    try b.sendEnvelope(std.testing.allocator, "node-a", .{
        .kind = .response,
        .correlation_id = 7,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{ .discovery = true },
        .payload = "ok",
    });

    const ok = try a.expectResponse(std.testing.allocator, 7);
    defer ok.deinit(std.testing.allocator);

    try b.sendEnvelope(std.testing.allocator, "node-a", .{
        .kind = .response,
        .correlation_id = 8,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = "wrong",
    });
    try std.testing.expectError(MeshError.InvalidPeerRecord, a.expectResponse(std.testing.allocator, 7));
}

test "session endpoint sendRequest/sendResponse and expectResponseFrom work together" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const client = Endpoint{ .id = "node-client", .bus = &bus };
    const server = Endpoint{ .id = "node-server", .bus = &bus };

    try client.sendRequest(std.testing.allocator, "node-server", 13, .{ .discovery = true }, "payload");
    const request = (try server.recvEnvelope(std.testing.allocator)).?;
    defer request.deinit(std.testing.allocator);
    try std.testing.expectEqual(control.Kind.request, request.envelope.kind);

    try server.sendResponse(std.testing.allocator, "node-client", 13, .{ .discovery = true }, "ok");
    const response = try client.expectResponseFrom(std.testing.allocator, "node-server", 13);
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ok", response.envelope.payload);
}
