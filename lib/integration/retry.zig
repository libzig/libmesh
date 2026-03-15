const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const Policy = struct {
    max_attempts: usize = 3,
    base_delay_ms: u32 = 25,
    max_delay_ms: u32 = 400,
};

pub const AttemptFn = *const fn (ctx: *anyopaque, attempt_index: usize) MeshError!void;

pub fn delayMs(policy: Policy, attempt_index: usize) u32 {
    var delay = policy.base_delay_ms;
    var i: usize = 0;
    while (i < attempt_index) : (i += 1) {
        delay = @min(policy.max_delay_ms, delay * 2);
    }
    return delay;
}

pub fn isRetryable(err: MeshError) bool {
    return switch (err) {
        MeshError.NotFound,
        MeshError.BufferTooSmall,
        => true,
        else => false,
    };
}

pub fn run(policy: Policy, ctx: *anyopaque, attempt_fn: AttemptFn) MeshError!usize {
    if (policy.max_attempts == 0) return MeshError.InvalidVersion;

    var attempt: usize = 0;
    while (attempt < policy.max_attempts) : (attempt += 1) {
        attempt_fn(ctx, attempt) catch |err| {
            if (!isRetryable(err) or attempt + 1 >= policy.max_attempts) return err;
            continue;
        };
        return attempt + 1;
    }
    return MeshError.NotFound;
}

test "retry run succeeds after retryable failures" {
    const Outcome = enum { ok, retry, fatal };
    const Context = struct {
        outcomes: []const Outcome,
        index: usize = 0,
    };
    const Driver = struct {
        fn attempt(ctx_ptr: *anyopaque, _: usize) MeshError!void {
            const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
            const outcome = ctx.outcomes[ctx.index];
            ctx.index += 1;
            return switch (outcome) {
                .ok => {},
                .retry => MeshError.NotFound,
                .fatal => MeshError.AccessDenied,
            };
        }
    };

    var ctx = Context{
        .outcomes = &[_]Outcome{ .retry, .retry, .ok },
    };
    const attempts = try run(.{ .max_attempts = 4 }, &ctx, Driver.attempt);
    try std.testing.expectEqual(@as(usize, 3), attempts);
}

test "retry run stops immediately on fatal error" {
    const Outcome = enum { fatal };
    const Context = struct {
        outcomes: []const Outcome,
        index: usize = 0,
    };
    const Driver = struct {
        fn attempt(ctx_ptr: *anyopaque, _: usize) MeshError!void {
            const ctx: *Context = @ptrCast(@alignCast(ctx_ptr));
            _ = ctx.outcomes[ctx.index];
            ctx.index += 1;
            return MeshError.AccessDenied;
        }
    };

    var ctx = Context{
        .outcomes = &[_]Outcome{.fatal},
    };
    try std.testing.expectError(MeshError.AccessDenied, run(.{ .max_attempts = 3 }, &ctx, Driver.attempt));
}

test "retry delay caps at max backoff" {
    const policy = Policy{
        .base_delay_ms = 20,
        .max_delay_ms = 70,
    };
    try std.testing.expectEqual(@as(u32, 20), delayMs(policy, 0));
    try std.testing.expectEqual(@as(u32, 40), delayMs(policy, 1));
    try std.testing.expectEqual(@as(u32, 70), delayMs(policy, 2));
    try std.testing.expectEqual(@as(u32, 70), delayMs(policy, 3));
}
