const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;
const routing_policy = @import("../routing/policy.zig");
const orchestrator = @import("../routing/orchestrator.zig");
const libdice_contract = @import("libdice_contract.zig");

pub const Outcome = enum {
    direct,
    direct_after_signaling,
    relay,
};

pub const Result = struct {
    outcome: Outcome,
    decision: routing_policy.Decision,
    contract: libdice_contract.Contract,
};

pub fn connect(
    allocator: std.mem.Allocator,
    peer: ResolvedPeer,
    runtime: routing_policy.Runtime,
) MeshError!Result {
    const plan = try orchestrator.buildPlan(allocator, .{}, peer, runtime);
    defer plan.deinit(allocator);

    const contract = libdice_contract.fromDecision(plan.decision);
    try libdice_contract.validateBoundary(contract);

    return .{
        .decision = plan.decision,
        .contract = contract,
        .outcome = switch (plan.decision) {
            .direct => .direct,
            .signaling_then_direct => .direct_after_signaling,
            .relay => .relay,
            .none => return MeshError.NotFound,
        },
    };
}

fn fixtureResolvedPeer() ResolvedPeer {
    const libself = @import("libself");
    const key_pair = libself.identity.KeyPair.fromSeed([_]u8{0xd1} ** 32) catch unreachable;
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.220", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-orch", .relay_address = "relay.example.net:8443", .priority = 3 },
    };
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 3 },
    };
    return .{
        .record = .{
            .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &hints,
        },
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "node orchestrator returns direct outcome when direct path is available" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{});
    try std.testing.expectEqual(Outcome.direct, result.outcome);
    try std.testing.expectEqual(routing_policy.Decision.direct, result.decision);
}

test "node orchestrator returns direct_after_signaling when traversal is needed" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{
        .needs_traversal = true,
        .dice_available = true,
    });
    try std.testing.expectEqual(Outcome.direct_after_signaling, result.outcome);
    try std.testing.expect(result.contract.invoke_external_libdice);
}

test "node orchestrator returns relay outcome when direct route is disabled" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{
        .direct_disabled = true,
    });
    try std.testing.expectEqual(Outcome.relay, result.outcome);
    try std.testing.expect(result.contract.use_relay_fallback);
}
