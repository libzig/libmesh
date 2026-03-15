const std = @import("std");

pub const MeshError = error{
    InvalidPeerRecord,
    InvalidEndpoint,
    InvalidRelayHint,
    InvalidSignature,
    InvalidVersion,
    Expired,
    NotFound,
    AccessDenied,
    BufferTooSmall,
    Duplicate,
};

test "MeshError set is usable in error unions" {
    const Result = MeshError!u8;
    const value: Result = 1;
    try std.testing.expectEqual(@as(u8, 1), try value);
}
