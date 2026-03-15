const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const retry = @import("retry.zig");
const control = @import("control_session.zig");
const session_endpoint = @import("session_endpoint.zig");

pub const PumpFn = *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) MeshError!bool;
pub const ValidateFn = *const fn (ctx: *anyopaque, response: control.Envelope) MeshError!void;

const AttemptContext = struct {
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    envelope: control.Envelope,
    expected_from: ?[]const u8 = null,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
    allocator: std.mem.Allocator,
    response: ?session_endpoint.OwnedEnvelope = null,
};

fn attempt(ctx_ptr: *anyopaque, _: usize) MeshError!void {
    const ctx: *AttemptContext = @ptrCast(@alignCast(ctx_ptr));
    try ctx.endpoint.sendEnvelope(ctx.allocator, ctx.to, ctx.envelope);
    const pumped = try ctx.pump_fn(ctx.pump_ctx, ctx.allocator);
    if (!pumped) return MeshError.NotFound;
    ctx.response = if (ctx.expected_from) |expected_from|
        try ctx.endpoint.expectResponseFrom(ctx.allocator, expected_from, ctx.envelope.correlation_id)
    else
        try ctx.endpoint.expectResponse(ctx.allocator, ctx.envelope.correlation_id);
}

pub fn requestResponse(
    allocator: std.mem.Allocator,
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    envelope: control.Envelope,
    policy: retry.Policy,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
) MeshError!session_endpoint.OwnedEnvelope {
    var ctx = AttemptContext{
        .endpoint = endpoint,
        .to = to,
        .envelope = envelope,
        .pump_ctx = pump_ctx,
        .pump_fn = pump_fn,
        .allocator = allocator,
    };
    _ = try retry.run(policy, &ctx, attempt);
    return ctx.response orelse MeshError.NotFound;
}

pub fn requestResponseFrom(
    allocator: std.mem.Allocator,
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    expected_from: []const u8,
    envelope: control.Envelope,
    policy: retry.Policy,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
) MeshError!session_endpoint.OwnedEnvelope {
    var ctx = AttemptContext{
        .endpoint = endpoint,
        .to = to,
        .envelope = envelope,
        .expected_from = expected_from,
        .pump_ctx = pump_ctx,
        .pump_fn = pump_fn,
        .allocator = allocator,
    };
    _ = try retry.run(policy, &ctx, attempt);
    return ctx.response orelse MeshError.NotFound;
}

const ValidateAttemptContext = struct {
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    envelope: control.Envelope,
    expected_from: ?[]const u8 = null,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
    validate_ctx: *anyopaque,
    validate_fn: ValidateFn,
    allocator: std.mem.Allocator,
    response: ?session_endpoint.OwnedEnvelope = null,
};

fn attemptValidated(ctx_ptr: *anyopaque, _: usize) MeshError!void {
    const ctx: *ValidateAttemptContext = @ptrCast(@alignCast(ctx_ptr));
    try ctx.endpoint.sendEnvelope(ctx.allocator, ctx.to, ctx.envelope);
    const pumped = try ctx.pump_fn(ctx.pump_ctx, ctx.allocator);
    if (!pumped) return MeshError.NotFound;
    const response = if (ctx.expected_from) |expected_from|
        try ctx.endpoint.expectResponseFrom(ctx.allocator, expected_from, ctx.envelope.correlation_id)
    else
        try ctx.endpoint.expectResponse(ctx.allocator, ctx.envelope.correlation_id);
    errdefer response.deinit(ctx.allocator);
    try ctx.validate_fn(ctx.validate_ctx, response.envelope);
    ctx.response = response;
}

pub fn requestResponseValidated(
    allocator: std.mem.Allocator,
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    envelope: control.Envelope,
    policy: retry.Policy,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
    validate_ctx: *anyopaque,
    validate_fn: ValidateFn,
) MeshError!session_endpoint.OwnedEnvelope {
    var ctx = ValidateAttemptContext{
        .endpoint = endpoint,
        .to = to,
        .envelope = envelope,
        .pump_ctx = pump_ctx,
        .pump_fn = pump_fn,
        .validate_ctx = validate_ctx,
        .validate_fn = validate_fn,
        .allocator = allocator,
    };
    _ = try retry.run(policy, &ctx, attemptValidated);
    return ctx.response orelse MeshError.NotFound;
}

pub fn requestResponseValidatedFrom(
    allocator: std.mem.Allocator,
    endpoint: session_endpoint.Endpoint,
    to: []const u8,
    expected_from: []const u8,
    envelope: control.Envelope,
    policy: retry.Policy,
    pump_ctx: *anyopaque,
    pump_fn: PumpFn,
    validate_ctx: *anyopaque,
    validate_fn: ValidateFn,
) MeshError!session_endpoint.OwnedEnvelope {
    var ctx = ValidateAttemptContext{
        .endpoint = endpoint,
        .to = to,
        .envelope = envelope,
        .expected_from = expected_from,
        .pump_ctx = pump_ctx,
        .pump_fn = pump_fn,
        .validate_ctx = validate_ctx,
        .validate_fn = validate_fn,
        .allocator = allocator,
    };
    _ = try retry.run(policy, &ctx, attemptValidated);
    return ctx.response orelse MeshError.NotFound;
}

test "request exchange retries until pump provides a response" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const client = session_endpoint.Endpoint{ .id = "node-a", .bus = &bus };
    const server = session_endpoint.Endpoint{ .id = "node-b", .bus = &bus };

    const PumpContext = struct {
        attempts: usize = 0,
        server_ep: session_endpoint.Endpoint,
    };
    const Pump = struct {
        fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) MeshError!bool {
            const ctx: *PumpContext = @ptrCast(@alignCast(ctx_ptr));
            ctx.attempts += 1;
            if (ctx.attempts == 1) return false;

            const incoming = (try ctx.server_ep.recvEnvelope(allocator)) orelse return false;
            defer incoming.deinit(allocator);
            try ctx.server_ep.sendEnvelope(allocator, "node-a", .{
                .kind = .response,
                .correlation_id = incoming.envelope.correlation_id,
                .version = .{ .major = 1, .minor = 0, .patch = 0 },
                .capabilities = .{ .discovery = true },
                .payload = "ok",
            });
            return true;
        }
    };

    var pump_ctx = PumpContext{
        .server_ep = server,
    };
    const response = try requestResponse(
        std.testing.allocator,
        client,
        "node-b",
        .{
            .kind = .request,
            .correlation_id = 1,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = "hello",
        },
        .{ .max_attempts = 3 },
        &pump_ctx,
        Pump.run,
    );
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ok", response.envelope.payload);
    try std.testing.expectEqual(@as(usize, 2), pump_ctx.attempts);
}

test "request exchange returns retry exhaustion error when no response arrives" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const client = session_endpoint.Endpoint{ .id = "node-a", .bus = &bus };
    var empty_ctx: u8 = 0;
    const Pump = struct {
        fn run(_: *anyopaque, _: std.mem.Allocator) MeshError!bool {
            return false;
        }
    };

    try std.testing.expectError(
        MeshError.NotFound,
        requestResponse(
            std.testing.allocator,
            client,
            "node-b",
            .{
                .kind = .request,
                .correlation_id = 2,
                .version = .{ .major = 1, .minor = 0, .patch = 0 },
                .capabilities = .{ .discovery = true },
                .payload = "hello",
            },
            .{ .max_attempts = 2 },
            &empty_ctx,
            Pump.run,
        ),
    );
}

test "request exchange validated retries when semantic response check fails" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const client = session_endpoint.Endpoint{ .id = "node-a", .bus = &bus };
    const server = session_endpoint.Endpoint{ .id = "node-b", .bus = &bus };

    const PumpContext = struct {
        attempts: usize = 0,
        server_ep: session_endpoint.Endpoint,
    };
    const Pump = struct {
        fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) MeshError!bool {
            const ctx: *PumpContext = @ptrCast(@alignCast(ctx_ptr));
            ctx.attempts += 1;
            const incoming = (try ctx.server_ep.recvEnvelope(allocator)) orelse return false;
            defer incoming.deinit(allocator);
            const payload = if (ctx.attempts == 1) "bad" else "ok";
            try ctx.server_ep.sendEnvelope(allocator, "node-a", .{
                .kind = .response,
                .correlation_id = incoming.envelope.correlation_id,
                .version = .{ .major = 1, .minor = 0, .patch = 0 },
                .capabilities = .{ .discovery = true },
                .payload = payload,
            });
            return true;
        }
    };

    const Validate = struct {
        fn run(_: *anyopaque, response: control.Envelope) MeshError!void {
            if (!std.mem.eql(u8, response.payload, "ok")) return MeshError.NotFound;
        }
    };

    var pump_ctx = PumpContext{ .server_ep = server };
    var validate_ctx: u8 = 0;
    const response = try requestResponseValidated(
        std.testing.allocator,
        client,
        "node-b",
        .{
            .kind = .request,
            .correlation_id = 3,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = "hello",
        },
        .{ .max_attempts = 3 },
        &pump_ctx,
        Pump.run,
        &validate_ctx,
        Validate.run,
    );
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ok", response.envelope.payload);
    try std.testing.expectEqual(@as(usize, 2), pump_ctx.attempts);
}

test "request exchange from-source variants reject spoofed responder" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    const client = session_endpoint.Endpoint{ .id = "node-a", .bus = &bus };
    const legit = session_endpoint.Endpoint{ .id = "node-b", .bus = &bus };
    const spoof = session_endpoint.Endpoint{ .id = "node-x", .bus = &bus };

    const PumpContext = struct {
        first: bool = true,
        legit_ep: session_endpoint.Endpoint,
        spoof_ep: session_endpoint.Endpoint,
    };
    const Pump = struct {
        fn run(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) MeshError!bool {
            const ctx: *PumpContext = @ptrCast(@alignCast(ctx_ptr));
            const incoming = (try ctx.legit_ep.recvEnvelope(allocator)) orelse return false;
            defer incoming.deinit(allocator);
            if (ctx.first) {
                ctx.first = false;
                try ctx.spoof_ep.sendResponse(allocator, "node-a", incoming.envelope.correlation_id, .{ .discovery = true }, "spoof");
            } else {
                try ctx.legit_ep.sendResponse(allocator, "node-a", incoming.envelope.correlation_id, .{ .discovery = true }, "ok");
            }
            return true;
        }
    };

    var pump_ctx = PumpContext{
        .legit_ep = legit,
        .spoof_ep = spoof,
    };
    const response = try requestResponseFrom(
        std.testing.allocator,
        client,
        "node-b",
        "node-b",
        .{
            .kind = .request,
            .correlation_id = 10,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .capabilities = .{ .discovery = true },
            .payload = "hello",
        },
        .{ .max_attempts = 3 },
        &pump_ctx,
        Pump.run,
    );
    defer response.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("ok", response.envelope.payload);
}
