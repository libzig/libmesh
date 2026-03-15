const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;
const libfast_integration = @import("../integration/libfast.zig");
const policy_mod = @import("policy.zig");

pub const Plan = struct {
    decision: policy_mod.Decision,
    targets: []libfast_integration.ConnectionTarget,

    pub fn deinit(self: Plan, allocator: std.mem.Allocator) void {
        allocator.free(self.targets);
    }
};

pub fn buildPlan(
    allocator: std.mem.Allocator,
    policy: policy_mod.Policy,
    peer: ResolvedPeer,
    runtime: policy_mod.Runtime,
) MeshError!Plan {
    const decision = policy.decide(peer, runtime);
    if (decision == .none) return MeshError.NotFound;

    const all_targets = try libfast_integration.resolveTargets(allocator, peer);
    defer allocator.free(all_targets);

    var selected = std.ArrayList(libfast_integration.ConnectionTarget).empty;
    defer selected.deinit(allocator);
    for (all_targets) |target| {
        switch (decision) {
            .direct, .signaling_then_direct => switch (target) {
                .direct => selected.append(allocator, target) catch return MeshError.BufferTooSmall,
                else => {},
            },
            .relay => switch (target) {
                .relay => selected.append(allocator, target) catch return MeshError.BufferTooSmall,
                else => {},
            },
            .none => unreachable,
        }
    }
    if (selected.items.len == 0) return MeshError.NotFound;

    return .{
        .decision = decision,
        .targets = selected.toOwnedSlice(allocator) catch return MeshError.BufferTooSmall,
    };
}

fn fixtureResolvedPeer() ResolvedPeer {
    const libself = @import("libself");
    const key_pair = libself.identity.KeyPair.fromSeed([_]u8{0x97} ** 32) catch unreachable;
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.40", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-orch", .relay_address = "relay.example.net:8443", .priority = 1 },
    };
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 1 },
    };
    return .{
        .record = .{
            .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 1,
            .expires_at_ms = 5000,
            .endpoints = &endpoints,
            .relay_hints = &hints,
        },
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "orchestrator builds direct plan by default" {
    const resolved = fixtureResolvedPeer();
    const plan = try buildPlan(std.testing.allocator, .{}, resolved, .{});
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(policy_mod.Decision.direct, plan.decision);
    try std.testing.expectEqual(@as(usize, 1), plan.targets.len);
    switch (plan.targets[0]) {
        .direct => {},
        else => return error.TestUnexpectedResult,
    }
}

test "orchestrator builds signaling_then_direct plan when traversal is needed" {
    const resolved = fixtureResolvedPeer();
    const plan = try buildPlan(std.testing.allocator, .{}, resolved, .{
        .needs_traversal = true,
        .dice_available = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(policy_mod.Decision.signaling_then_direct, plan.decision);
    switch (plan.targets[0]) {
        .direct => {},
        else => return error.TestUnexpectedResult,
    }
}

test "orchestrator builds relay plan when direct path is disabled" {
    const resolved = fixtureResolvedPeer();
    const plan = try buildPlan(std.testing.allocator, .{}, resolved, .{
        .direct_disabled = true,
    });
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(policy_mod.Decision.relay, plan.decision);
    try std.testing.expectEqual(@as(usize, 1), plan.targets.len);
    switch (plan.targets[0]) {
        .relay => {},
        else => return error.TestUnexpectedResult,
    }
}
