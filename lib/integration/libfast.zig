const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const PublishedEndpoint = @import("../peer/endpoint.zig").PublishedEndpoint;
const RelayHint = @import("../peer/relay_hint.zig").RelayHint;
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

pub const ConnectionTarget = union(enum) {
    direct: struct {
        host: []const u8,
        port: u16,
        alpn: ?[]const u8,
    },
    relay: struct {
        relay_id: []const u8,
        host: []const u8,
        port: u16,
        alpn: []const u8,
    },
};

pub fn endpointToTarget(endpoint: PublishedEndpoint) MeshError!ConnectionTarget {
    try endpoint.validate();
    return .{
        .direct = .{
            .host = endpoint.host,
            .port = endpoint.port,
            .alpn = endpoint.alpn,
        },
    };
}

pub fn relayHintToTarget(hint: RelayHint) MeshError!ConnectionTarget {
    try hint.validate();
    const idx = std.mem.lastIndexOfScalar(u8, hint.relay_address, ':') orelse return MeshError.InvalidRelayHint;
    const host = hint.relay_address[0..idx];
    const port = std.fmt.parseInt(u16, hint.relay_address[idx + 1 ..], 10) catch return MeshError.InvalidRelayHint;

    return .{
        .relay = .{
            .relay_id = hint.relay_id,
            .host = host,
            .port = port,
            .alpn = hint.relay_alpn,
        },
    };
}

pub fn resolveTargets(allocator: std.mem.Allocator, peer: ResolvedPeer) MeshError![]ConnectionTarget {
    const routes = peer.allRoutes(allocator) catch return MeshError.BufferTooSmall;
    defer allocator.free(routes);

    var targets = allocator.alloc(ConnectionTarget, routes.len) catch return MeshError.BufferTooSmall;
    for (routes, 0..) |route, idx| {
        switch (route.kind) {
            .direct => {
                if (peer.record.endpoints.len == 0) return MeshError.NotFound;
                targets[idx] = try endpointToTarget(peer.record.endpoints[0]);
            },
            .relay => {
                if (peer.record.relay_hints.len == 0) return MeshError.NotFound;
                targets[idx] = try relayHintToTarget(peer.record.relay_hints[0]);
            },
        }
    }
    return targets;
}

test "endpointToTarget converts direct endpoint to connection target" {
    const target = try endpointToTarget(.{
        .host = "203.0.113.61",
        .port = 4433,
        .alpn = "mesh/1",
    });
    switch (target) {
        .direct => |direct| {
            try std.testing.expectEqualStrings("203.0.113.61", direct.host);
            try std.testing.expectEqual(@as(u16, 4433), direct.port);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "relayHintToTarget parses relay host and port" {
    const target = try relayHintToTarget(.{
        .relay_id = "relay-z",
        .relay_address = "relay.example.net:8443",
    });
    switch (target) {
        .relay => |relay| {
            try std.testing.expectEqualStrings("relay.example.net", relay.host);
            try std.testing.expectEqual(@as(u16, 8443), relay.port);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "resolveTargets materializes ordered direct and relay targets" {
    const key_pair = try @import("libself").identity.KeyPair.fromSeed([_]u8{0x71} ** 32);
    const endpoints = [_]PublishedEndpoint{
        .{ .host = "203.0.113.62", .port = 4433, .priority = 10 },
    };
    const hints = [_]RelayHint{
        .{ .relay_id = "relay-r", .relay_address = "relay.example.net:7443", .priority = 1 },
    };
    const record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = @import("libself").NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    const direct_routes = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay_routes = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 5 },
    };

    const resolved = ResolvedPeer{
        .record = record,
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };

    const allocator = std.testing.allocator;
    const targets = try resolveTargets(allocator, resolved);
    defer allocator.free(targets);

    try std.testing.expectEqual(@as(usize, 2), targets.len);
    switch (targets[0]) {
        .direct => {},
        else => return error.TestUnexpectedResult,
    }
    switch (targets[1]) {
        .relay => {},
        else => return error.TestUnexpectedResult,
    }
}
