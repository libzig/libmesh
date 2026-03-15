const std = @import("std");

pub const ProtocolVersion = struct {
    major: u16,
    minor: u16,
    patch: u16 = 0,

    pub fn compare(a: ProtocolVersion, b: ProtocolVersion) std.math.Order {
        if (a.major < b.major) return .lt;
        if (a.major > b.major) return .gt;
        if (a.minor < b.minor) return .lt;
        if (a.minor > b.minor) return .gt;
        if (a.patch < b.patch) return .lt;
        if (a.patch > b.patch) return .gt;
        return .eq;
    }
};

pub const current = ProtocolVersion{ .major = 0, .minor = 1, .patch = 0 };

test "version comparison is lexicographic over semantic fields" {
    const older = ProtocolVersion{ .major = 0, .minor = 0, .patch = 9 };
    const newer = ProtocolVersion{ .major = 0, .minor = 1, .patch = 0 };
    try std.testing.expectEqual(std.math.Order.lt, ProtocolVersion.compare(older, newer));
    try std.testing.expectEqual(std.math.Order.eq, ProtocolVersion.compare(current, newer));
}
