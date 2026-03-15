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
    std.debug.print("orchestrator outcome={s}\n", .{@tagName(result.outcome)});
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
