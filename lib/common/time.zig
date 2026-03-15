const std = @import("std");

pub const TimestampMs = u64;

pub fn nowMs() TimestampMs {
    const current = std.time.milliTimestamp();
    if (current < 0) return 0;
    return @intCast(current);
}

pub fn expired(now_ms: TimestampMs, expires_at_ms: TimestampMs) bool {
    return now_ms > expires_at_ms;
}

pub fn remainingMs(now_ms: TimestampMs, expires_at_ms: TimestampMs) ?u64 {
    if (now_ms >= expires_at_ms) return null;
    return expires_at_ms - now_ms;
}

test "time helpers detect expiry and remaining duration" {
    try std.testing.expect(!expired(10, 10));
    try std.testing.expect(expired(11, 10));
    try std.testing.expectEqual(@as(?u64, 5), remainingMs(5, 10));
    try std.testing.expectEqual(@as(?u64, null), remainingMs(10, 10));
}

test "time nowMs returns a non-zero unix millisecond timestamp" {
    try std.testing.expect(nowMs() > 0);
}
