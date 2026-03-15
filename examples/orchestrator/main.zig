const std = @import("std");
const libmesh = @import("libmesh");

pub fn main() !void {
    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x71} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.230", .port = 4433, .priority = 10 },
    };
    const relay_hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-orchestrator", .relay_address = "relay.example.net:8443", .priority = 3 },
    };
    const direct_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .relay, .priority = 3 },
    };
    const resolved = libmesh.peer.resolved_peer.ResolvedPeer{
        .record = .{
            .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &relay_hints,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };
    const result = try libmesh.integration.node_orchestrator.connect(std.heap.page_allocator, resolved, .{
        .needs_traversal = true,
        .dice_available = true,
    });
    const DriverCtx = struct {};
    const DriverImpl = struct {
        fn connect(_: *anyopaque, target: libmesh.integration.libfast.ConnectionTarget) libmesh.common.errors.MeshError!libmesh.integration.libfast_adapter.ConnectionId {
            return switch (target) {
                .direct => 9201,
                .relay => libmesh.common.errors.MeshError.NotFound,
            };
        }
        fn send(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId, _: []const u8) libmesh.common.errors.MeshError!void {}
        fn recv(_: *anyopaque, _: std.mem.Allocator, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!?[]u8 {
            return null;
        }
        fn close(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!void {}
    };
    var driver_ctx = DriverCtx{};
    const opened = try libmesh.api.connectPeerViaDriverDefault(std.heap.page_allocator, resolved, .{
        .ctx = &driver_ctx,
        .vtable = &.{
            .connect = DriverImpl.connect,
            .send = DriverImpl.send,
            .recv = DriverImpl.recv,
            .close = DriverImpl.close,
        },
    });
    std.debug.print("orchestrator outcome={s} opened_conn={d}\n", .{ @tagName(result.outcome), opened.session.connection_id });
}

test "orchestrator example returns relay outcome when direct is disabled" {
    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x72} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.231", .port = 4433, .priority = 10 },
    };
    const relay_hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-orchestrator-2", .relay_address = "relay.example.net:9443", .priority = 9 },
    };
    const direct_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .relay, .priority = 9 },
    };
    const resolved = libmesh.peer.resolved_peer.ResolvedPeer{
        .record = .{
            .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &relay_hints,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };

    const result = try libmesh.integration.node_orchestrator.connect(std.testing.allocator, resolved, .{
        .direct_disabled = true,
    });
    try std.testing.expectEqual(libmesh.integration.node_orchestrator.Outcome.relay, result.outcome);
}

test "orchestrator example opens direct session through driver helper" {
    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x73} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.232", .port = 4433, .priority = 10 },
    };
    const relay_hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-orchestrator-3", .relay_address = "relay.example.net:7443", .priority = 5 },
    };
    const direct_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .relay, .priority = 5 },
    };
    const resolved = libmesh.peer.resolved_peer.ResolvedPeer{
        .record = .{
            .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &relay_hints,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };
    const DriverCtx = struct {};
    const DriverImpl = struct {
        fn connect(_: *anyopaque, target: libmesh.integration.libfast.ConnectionTarget) libmesh.common.errors.MeshError!libmesh.integration.libfast_adapter.ConnectionId {
            return switch (target) {
                .direct => 9301,
                .relay => libmesh.common.errors.MeshError.NotFound,
            };
        }
        fn send(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId, _: []const u8) libmesh.common.errors.MeshError!void {}
        fn recv(_: *anyopaque, _: std.mem.Allocator, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!?[]u8 {
            return null;
        }
        fn close(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!void {}
    };
    var driver_ctx = DriverCtx{};
    const opened = try libmesh.api.connectPeerViaDriverDefault(std.testing.allocator, resolved, .{
        .ctx = &driver_ctx,
        .vtable = &.{
            .connect = DriverImpl.connect,
            .send = DriverImpl.send,
            .recv = DriverImpl.recv,
            .close = DriverImpl.close,
        },
    });
    try std.testing.expectEqual(libmesh.routing.policy.Decision.direct, opened.result.decision);
    try std.testing.expectEqual(@as(libmesh.integration.libfast_adapter.ConnectionId, 9301), opened.session.connection_id);
    try std.testing.expect(!opened.used_relay_fallback);
}

test "orchestrator example falls back to relay session through driver helper" {
    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x74} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.233", .port = 4433, .priority = 10 },
    };
    const relay_hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-orchestrator-4", .relay_address = "relay.example.net:7443", .priority = 7 },
    };
    const direct_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]libmesh.peer.route_candidate.RouteCandidate{
        .{ .kind = .relay, .priority = 7 },
    };
    const resolved = libmesh.peer.resolved_peer.ResolvedPeer{
        .record = .{
            .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &relay_hints,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };
    const DriverCtx = struct {};
    const DriverImpl = struct {
        fn connect(_: *anyopaque, target: libmesh.integration.libfast.ConnectionTarget) libmesh.common.errors.MeshError!libmesh.integration.libfast_adapter.ConnectionId {
            return switch (target) {
                .direct => libmesh.common.errors.MeshError.NotFound,
                .relay => 9401,
            };
        }
        fn send(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId, _: []const u8) libmesh.common.errors.MeshError!void {}
        fn recv(_: *anyopaque, _: std.mem.Allocator, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!?[]u8 {
            return null;
        }
        fn close(_: *anyopaque, _: libmesh.integration.libfast_adapter.ConnectionId) libmesh.common.errors.MeshError!void {}
    };
    var driver_ctx = DriverCtx{};
    const opened = try libmesh.api.connectPeerViaDriverDefault(std.testing.allocator, resolved, .{
        .ctx = &driver_ctx,
        .vtable = &.{
            .connect = DriverImpl.connect,
            .send = DriverImpl.send,
            .recv = DriverImpl.recv,
            .close = DriverImpl.close,
        },
    });
    try std.testing.expectEqual(libmesh.routing.policy.Decision.relay, opened.result.decision);
    try std.testing.expectEqual(@as(libmesh.integration.libfast_adapter.ConnectionId, 9401), opened.session.connection_id);
    try std.testing.expect(opened.used_relay_fallback);
}
