const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const control = @import("../integration/control_session.zig");
const guard = @import("../integration/negotiation_guard.zig");
const Endpoint = @import("../integration/session_endpoint.zig").Endpoint;
const discovery_client = @import("client.zig");
const discovery_server = @import("server.zig");
const protocol = @import("protocol.zig");
const peer_record = @import("../peer/peer_record.zig");

pub const SessionTransport = struct {
    client_id: []const u8,
    server_id: []const u8,
    client: Endpoint,
    server: Endpoint,
    handler: discovery_server.Server,

    pub fn requestPublish(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64, record: peer_record.PeerRecord) MeshError!void {
        const payload = try discovery_client.buildPublish(allocator, correlation_id, record);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = payload,
        });
    }

    pub fn requestLookup(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64, node_id: @import("libself").NodeId) MeshError!void {
        const payload = try discovery_client.buildLookup(allocator, correlation_id, node_id);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = payload,
        });
    }

    pub fn requestRefresh(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64, record: peer_record.PeerRecord) MeshError!void {
        const payload = try discovery_client.buildRefresh(allocator, correlation_id, record);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = payload,
        });
    }

    pub fn requestWithdraw(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64, node_id: @import("libself").NodeId) MeshError!void {
        const payload = try discovery_client.buildWithdraw(allocator, correlation_id, node_id);
        defer allocator.free(payload);
        try self.client.sendEnvelope(allocator, self.server_id, .{
            .kind = .request,
            .correlation_id = correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = payload,
        });
    }

    pub fn pumpServer(self: SessionTransport, allocator: std.mem.Allocator) MeshError!bool {
        const incoming = (try self.server.recvEnvelope(allocator)) orelse return false;
        defer incoming.deinit(allocator);
        if (incoming.envelope.kind != .request) return MeshError.InvalidPeerRecord;
        const negotiated = try guard.validate(.{
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
        }, incoming.envelope);
        try guard.requireCapability(negotiated, .discovery);

        const response_payload = try self.handler.handle(allocator, incoming.envelope.payload);
        defer allocator.free(response_payload);

        try self.server.sendEnvelope(allocator, self.client_id, .{
            .kind = .response,
            .correlation_id = incoming.envelope.correlation_id,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = response_payload,
        });
        return true;
    }

    pub fn recvLookup(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64) MeshError!discovery_client.ParsedPeerRecord {
        const response = try self.client.expectResponse(allocator, correlation_id);
        defer response.deinit(allocator);
        return discovery_client.parseLookupResponse(allocator, response.envelope.payload);
    }

    pub fn recvAck(self: SessionTransport, allocator: std.mem.Allocator, correlation_id: u64) MeshError!void {
        const response = try self.client.expectResponse(allocator, correlation_id);
        defer response.deinit(allocator);
        const decoded = try protocol.decode(response.envelope.payload);
        if (!std.mem.eql(u8, decoded.payload, "ok")) return MeshError.InvalidPeerRecord;
    }
};

test "discovery session transport publish lookup refresh withdraw flow works" {
    const libself = @import("libself");
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    var store = @import("store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();
    const transport = SessionTransport{
        .client_id = "node-client",
        .server_id = "node-server",
        .client = .{ .id = "node-client", .bus = &bus },
        .server = .{ .id = "node-server", .bus = &bus },
        .handler = .{ .store = &store },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xe1} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.210", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-session", .relay_address = "relay.example.net:7443" },
    };
    var record = peer_record.PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    try transport.requestPublish(std.testing.allocator, 1, record);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 1);

    try transport.requestLookup(std.testing.allocator, 2, record.node_id);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    var looked = try transport.recvLookup(std.testing.allocator, 2);
    defer looked.deinit();
    try std.testing.expect(try looked.record.verify(std.testing.allocator, kp.public_key));

    var refreshed = record;
    refreshed.expires_at_ms = 120;
    try refreshed.sign(std.testing.allocator, kp);
    try transport.requestRefresh(std.testing.allocator, 3, refreshed);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 3);

    try transport.requestWithdraw(std.testing.allocator, 4, refreshed.node_id);
    try std.testing.expect(try transport.pumpServer(std.testing.allocator));
    try transport.recvAck(std.testing.allocator, 4);
}

test "discovery session transport rejects mismatched major versions" {
    const libself = @import("libself");
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const transport = SessionTransport{
        .client_id = "node-client",
        .server_id = "node-server",
        .client = .{ .id = "node-client", .bus = &bus },
        .server = .{ .id = "node-server", .bus = &bus },
        .handler = .{ .store = &store },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xe2} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.211", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-session-v", .relay_address = "relay.example.net:8443" },
    };
    var record = peer_record.PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    const wire = try discovery_client.buildPublish(std.testing.allocator, 1, record);
    defer std.testing.allocator.free(wire);

    try transport.client.sendEnvelope(std.testing.allocator, "node-server", .{
        .kind = .request,
        .correlation_id = 1,
        .version = .{ .major = 2, .minor = 0, .patch = 0 },
        .capabilities = .{ .discovery = true },
        .payload = wire,
    });
    try std.testing.expectError(MeshError.InvalidVersion, transport.pumpServer(std.testing.allocator));
}

test "discovery session transport rejects missing discovery capability" {
    const libself = @import("libself");
    var bus = @import("../integration/session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const transport = SessionTransport{
        .client_id = "node-client",
        .server_id = "node-server",
        .client = .{ .id = "node-client", .bus = &bus },
        .server = .{ .id = "node-server", .bus = &bus },
        .handler = .{ .store = &store },
    };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xe3} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.212", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-session-c", .relay_address = "relay.example.net:9443" },
    };
    var record = peer_record.PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    const wire = try discovery_client.buildPublish(std.testing.allocator, 1, record);
    defer std.testing.allocator.free(wire);

    try transport.client.sendEnvelope(std.testing.allocator, "node-server", .{
        .kind = .request,
        .correlation_id = 1,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
        .capabilities = .{},
        .payload = wire,
    });
    try std.testing.expectError(MeshError.AccessDenied, transport.pumpServer(std.testing.allocator));
}
