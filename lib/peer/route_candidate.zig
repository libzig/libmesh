const std = @import("std");

pub const RouteKind = enum {
    direct,
    relay,
};

pub const RouteCandidate = struct {
    kind: RouteKind,
    priority: i16 = 0,
    label: []const u8 = "",

    pub fn betterThan(self: RouteCandidate, other: RouteCandidate) bool {
        if (self.kind != other.kind) return self.kind == .direct;
        return self.priority > other.priority;
    }
};

pub fn sortPreferred(routes: []RouteCandidate) void {
    if (routes.len < 2) return;
    var i: usize = 1;
    while (i < routes.len) : (i += 1) {
        var j = i;
        while (j > 0 and routes[j].betterThan(routes[j - 1])) : (j -= 1) {
            std.mem.swap(RouteCandidate, &routes[j], &routes[j - 1]);
        }
    }
}

test "direct route is preferred over relay route" {
    const direct = RouteCandidate{ .kind = .direct, .priority = 1 };
    const relay = RouteCandidate{ .kind = .relay, .priority = 999 };
    try std.testing.expect(direct.betterThan(relay));
}

test "sortPreferred orders direct first and by descending priority" {
    var routes = [_]RouteCandidate{
        .{ .kind = .relay, .priority = 10 },
        .{ .kind = .direct, .priority = 2 },
        .{ .kind = .direct, .priority = 5 },
    };
    sortPreferred(&routes);
    try std.testing.expectEqual(RouteKind.direct, routes[0].kind);
    try std.testing.expectEqual(@as(i16, 5), routes[0].priority);
    try std.testing.expectEqual(RouteKind.relay, routes[2].kind);
}
