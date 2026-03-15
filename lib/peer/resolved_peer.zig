const std = @import("std");
const PeerRecord = @import("peer_record.zig").PeerRecord;
const RouteCandidate = @import("route_candidate.zig").RouteCandidate;
const route_candidate = @import("route_candidate.zig");

pub const ResolvedPeer = struct {
    record: PeerRecord,
    direct_routes: []const RouteCandidate,
    relay_routes: []const RouteCandidate,

    pub fn allRoutes(self: ResolvedPeer, allocator: std.mem.Allocator) ![]RouteCandidate {
        var merged = try allocator.alloc(RouteCandidate, self.direct_routes.len + self.relay_routes.len);
        @memcpy(merged[0..self.direct_routes.len], self.direct_routes);
        @memcpy(merged[self.direct_routes.len..], self.relay_routes);
        route_candidate.sortPreferred(merged);
        return merged;
    }
};

test "ResolvedPeer allRoutes merges and sorts candidates" {
    const key_pair = try @import("libself").identity.KeyPair.fromSeed([_]u8{0x55} ** 32);
    const endpoints = [_]@import("endpoint.zig").PublishedEndpoint{};
    const hints = [_]@import("relay_hint.zig").RelayHint{};
    const record = PeerRecord{
        .node_id = @import("libself").NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 999,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };

    const direct = [_]RouteCandidate{
        .{ .kind = .direct, .priority = 2, .label = "direct-1" },
    };
    const relay = [_]RouteCandidate{
        .{ .kind = .relay, .priority = 100, .label = "relay-1" },
    };

    const resolved = ResolvedPeer{
        .record = record,
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
    const allocator = std.testing.allocator;
    const merged = try resolved.allRoutes(allocator);
    defer allocator.free(merged);

    try std.testing.expectEqual(@as(usize, 2), merged.len);
    try std.testing.expectEqual(@import("route_candidate.zig").RouteKind.direct, merged[0].kind);
}
