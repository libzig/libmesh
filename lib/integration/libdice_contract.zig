const std = @import("std");
const routing_policy = @import("../routing/policy.zig");
const MeshError = @import("../common/error.zig").MeshError;

pub const Contract = struct {
    use_signaling: bool = false,
    invoke_external_libdice: bool = false,
    use_relay_fallback: bool = false,
};

pub fn fromDecision(decision: routing_policy.Decision) Contract {
    return switch (decision) {
        .direct => .{
            .use_signaling = false,
            .invoke_external_libdice = false,
            .use_relay_fallback = false,
        },
        .signaling_then_direct => .{
            .use_signaling = true,
            .invoke_external_libdice = true,
            .use_relay_fallback = true,
        },
        .relay => .{
            .use_signaling = false,
            .invoke_external_libdice = false,
            .use_relay_fallback = true,
        },
        .none => .{},
    };
}

pub fn validateBoundary(contract: Contract) MeshError!void {
    // `libdice` use is only valid when signaling is active.
    if (contract.invoke_external_libdice and !contract.use_signaling) return MeshError.InvalidVersion;
}

pub fn carrySetupPayload(allocator: std.mem.Allocator, payload: []const u8) MeshError![]u8 {
    return allocator.dupe(u8, payload) catch MeshError.BufferTooSmall;
}

test "libdice contract maps routing decision to external orchestration behavior" {
    const direct = fromDecision(.direct);
    try std.testing.expect(!direct.use_signaling);
    try std.testing.expect(!direct.invoke_external_libdice);
    try validateBoundary(direct);

    const traverse = fromDecision(.signaling_then_direct);
    try std.testing.expect(traverse.use_signaling);
    try std.testing.expect(traverse.invoke_external_libdice);
    try validateBoundary(traverse);

    const relay = fromDecision(.relay);
    try std.testing.expect(relay.use_relay_fallback);
    try validateBoundary(relay);
}

test "libdice contract rejects invalid boundary combinations" {
    const bad = Contract{
        .use_signaling = false,
        .invoke_external_libdice = true,
    };
    try std.testing.expectError(MeshError.InvalidVersion, validateBoundary(bad));
}

test "libdice contract carries opaque setup payloads unchanged" {
    const payload = "candidate-bundle-v1";
    const copied = try carrySetupPayload(std.testing.allocator, payload);
    defer std.testing.allocator.free(copied);
    try std.testing.expectEqualStrings(payload, copied);
}
