const std = @import("std");
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;

pub const Decision = enum {
    direct,
    signaling_then_direct,
    relay,
    none,
};

pub const Runtime = struct {
    direct_disabled: bool = false,
    needs_traversal: bool = false,
    dice_available: bool = false,
};

pub const Policy = struct {
    allow_relay: bool = true,

    pub fn decide(self: Policy, peer: ResolvedPeer, runtime: Runtime) Decision {
        const has_direct = peer.record.endpoints.len > 0;
        const has_relay = peer.record.relay_hints.len > 0;

        if (!runtime.direct_disabled and has_direct) {
            if (runtime.needs_traversal and runtime.dice_available) return .signaling_then_direct;
            if (!runtime.needs_traversal) return .direct;
        }

        if (self.allow_relay and has_relay) return .relay;
        return .none;
    }
};

fn fixturePeer(has_direct: bool, has_relay: bool) ResolvedPeer {
    const key_pair = @import("libself").identity.KeyPair.fromSeed([_]u8{0x96} ** 32) catch unreachable;
    const node_id = @import("libself").NodeId.fromPublicKey(key_pair.public_key);
    const endpoints_empty = [_]@import("../peer/endpoint.zig").PublishedEndpoint{};
    const endpoints_one = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.30", .port = 4433 },
    };
    const relay_empty = [_]@import("../peer/relay_hint.zig").RelayHint{};
    const relay_one = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-r1", .relay_address = "relay.example.net:4433" },
    };
    const direct_routes = [_]@import("../peer/route_candidate.zig").RouteCandidate{};
    const relay_routes = [_]@import("../peer/route_candidate.zig").RouteCandidate{};

    return .{
        .record = .{
            .node_id = node_id,
            .published_at_ms = 1,
            .expires_at_ms = 1000,
            .endpoints = if (has_direct) &endpoints_one else &endpoints_empty,
            .relay_hints = if (has_relay) &relay_one else &relay_empty,
        },
        .direct_routes = &direct_routes,
        .relay_routes = &relay_routes,
    };
}

test "routing policy prefers direct when direct endpoint is available" {
    const policy = Policy{};
    const peer = fixturePeer(true, true);
    try std.testing.expectEqual(Decision.direct, policy.decide(peer, .{}));
}

test "routing policy selects signaling then direct when traversal is needed" {
    const policy = Policy{};
    const peer = fixturePeer(true, true);
    try std.testing.expectEqual(
        Decision.signaling_then_direct,
        policy.decide(peer, .{
            .needs_traversal = true,
            .dice_available = true,
        }),
    );
}

test "routing policy falls back to relay when direct path unavailable" {
    const policy = Policy{};
    const peer = fixturePeer(false, true);
    try std.testing.expectEqual(Decision.relay, policy.decide(peer, .{}));
}

test "routing policy returns none when no route exists" {
    const policy = Policy{};
    const peer = fixturePeer(false, false);
    try std.testing.expectEqual(Decision.none, policy.decide(peer, .{}));
}

test "routing policy falls back to relay when traversal is needed but libdice is unavailable" {
    const policy = Policy{};
    const peer = fixturePeer(true, true);
    try std.testing.expectEqual(
        Decision.relay,
        policy.decide(peer, .{
            .needs_traversal = true,
            .dice_available = false,
        }),
    );
}

test "routing policy returns none when traversal is needed, libdice is unavailable, and no relay exists" {
    const policy = Policy{};
    const peer = fixturePeer(true, false);
    try std.testing.expectEqual(
        Decision.none,
        policy.decide(peer, .{
            .needs_traversal = true,
            .dice_available = false,
        }),
    );
}
