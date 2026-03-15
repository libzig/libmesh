const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;
const ResolvedPeer = @import("../peer/resolved_peer.zig").ResolvedPeer;
const RouteCandidate = @import("../peer/route_candidate.zig").RouteCandidate;
const routing_policy = @import("../routing/policy.zig");
const orchestrator = @import("../routing/orchestrator.zig");
const libdice_contract = @import("libdice_contract.zig");
const libfast_adapter = @import("libfast_adapter.zig");

pub const Outcome = enum {
    direct,
    direct_after_signaling,
    relay,
};

pub const Result = struct {
    outcome: Outcome,
    decision: routing_policy.Decision,
    contract: libdice_contract.Contract,
};

pub const OpenSessionResult = struct {
    result: Result,
    session: libfast_adapter.Session,
    used_relay_fallback: bool = false,
};

pub fn connect(
    allocator: std.mem.Allocator,
    peer: ResolvedPeer,
    runtime: routing_policy.Runtime,
) MeshError!Result {
    const plan = try orchestrator.buildPlan(allocator, .{}, peer, runtime);
    defer plan.deinit(allocator);

    const contract = libdice_contract.fromDecision(plan.decision);
    try libdice_contract.validateBoundary(contract);

    return .{
        .decision = plan.decision,
        .contract = contract,
        .outcome = switch (plan.decision) {
            .direct => .direct,
            .signaling_then_direct => .direct_after_signaling,
            .relay => .relay,
            .none => return MeshError.NotFound,
        },
    };
}

pub fn connectAndOpenSession(
    allocator: std.mem.Allocator,
    peer: ResolvedPeer,
    runtime: routing_policy.Runtime,
    driver: libfast_adapter.Driver,
) MeshError!OpenSessionResult {
    const primary_plan = try orchestrator.buildPlan(allocator, .{}, peer, runtime);
    defer primary_plan.deinit(allocator);

    const primary_contract = libdice_contract.fromDecision(primary_plan.decision);
    try libdice_contract.validateBoundary(primary_contract);

    var result = Result{
        .decision = primary_plan.decision,
        .contract = primary_contract,
        .outcome = switch (primary_plan.decision) {
            .direct => .direct,
            .signaling_then_direct => .direct_after_signaling,
            .relay => .relay,
            .none => return MeshError.NotFound,
        },
    };
    var used_relay_fallback = false;
    const session = libfast_adapter.Session.openAny(driver, primary_plan.targets) catch |primary_err| blk: {
        if (primary_plan.decision != .direct and primary_plan.decision != .signaling_then_direct) return primary_err;
        var relay_runtime = runtime;
        relay_runtime.direct_disabled = true;
        const relay_plan = orchestrator.buildPlan(allocator, .{}, peer, relay_runtime) catch return primary_err;
        defer relay_plan.deinit(allocator);

        const relay_contract = libdice_contract.fromDecision(relay_plan.decision);
        try libdice_contract.validateBoundary(relay_contract);
        const relay_session = libfast_adapter.Session.openAny(driver, relay_plan.targets) catch return primary_err;
        result = .{
            .decision = relay_plan.decision,
            .contract = relay_contract,
            .outcome = switch (relay_plan.decision) {
                .direct => .direct,
                .signaling_then_direct => .direct_after_signaling,
                .relay => .relay,
                .none => return primary_err,
            },
        };
        used_relay_fallback = true;
        break :blk relay_session;
    };

    return .{
        .result = result,
        .session = session,
        .used_relay_fallback = used_relay_fallback,
    };
}

pub fn connectViaSessionControl(
    allocator: std.mem.Allocator,
    record: PeerRecord,
    runtime: routing_policy.Runtime,
    discovery_transport: @import("../discovery/session_transport.zig").SessionTransport,
    signaling_transport: ?@import("../signaling/session_transport.zig").SessionTransport,
    relay_transport: ?@import("../relay/session_transport.zig").SessionTransport,
) MeshError!Result {
    try discovery_transport.publishRoundTrip(allocator, 1001, record, .{ .max_attempts = 2 });
    var parsed = try discovery_transport.lookupRoundTrip(allocator, 1002, record.node_id, .{ .max_attempts = 2 });
    defer parsed.deinit();

    const direct_routes = if (parsed.record.endpoints.len == 0)
        &[_]RouteCandidate{}
    else
        &[_]RouteCandidate{.{ .kind = .direct, .priority = 10 }};
    const relay_routes = if (parsed.record.relay_hints.len == 0)
        &[_]RouteCandidate{}
    else
        &[_]RouteCandidate{.{ .kind = .relay, .priority = 9 }};

    const resolved = ResolvedPeer{
        .record = parsed.record,
        .direct_routes = direct_routes,
        .relay_routes = relay_routes,
    };
    const result = try connect(allocator, resolved, runtime);

    switch (result.decision) {
        .signaling_then_direct => {
            const signaling = signaling_transport orelse return MeshError.NotFound;
            try signaling.roundTrip(allocator, .{
                .kind = .setup_payload,
                .from_node = "node-a",
                .to_node = "node-b",
                .correlation_id = 1003,
                .payload = "ice:offer",
            }, .{ .max_attempts = 2 });
        },
        .relay => {
            const relay = relay_transport orelse return MeshError.NotFound;
            _ = try relay.roundTrip(allocator, .{
                .kind = .open,
                .session_id = 1004,
                .payload = "node-b",
            }, .{ .max_attempts = 2 }, true);
        },
        else => {},
    }
    return result;
}

fn fixtureResolvedPeer() ResolvedPeer {
    const libself = @import("libself");
    const key_pair = libself.identity.KeyPair.fromSeed([_]u8{0xd1} ** 32) catch unreachable;
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.220", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-orch", .relay_address = "relay.example.net:8443", .priority = 3 },
    };
    const direct = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .direct, .priority = 10 },
    };
    const relay = [_]@import("../peer/route_candidate.zig").RouteCandidate{
        .{ .kind = .relay, .priority = 3 },
    };
    return .{
        .record = .{
            .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
            .published_at_ms = 10,
            .expires_at_ms = 1000,
            .endpoints = &endpoints,
            .relay_hints = &hints,
        },
        .direct_routes = &direct,
        .relay_routes = &relay,
    };
}

test "node orchestrator returns direct outcome when direct path is available" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{});
    try std.testing.expectEqual(Outcome.direct, result.outcome);
    try std.testing.expectEqual(routing_policy.Decision.direct, result.decision);
}

test "node orchestrator returns direct_after_signaling when traversal is needed" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{
        .needs_traversal = true,
        .dice_available = true,
    });
    try std.testing.expectEqual(Outcome.direct_after_signaling, result.outcome);
    try std.testing.expect(result.contract.invoke_external_libdice);
}

test "node orchestrator returns relay outcome when direct route is disabled" {
    const result = try connect(std.testing.allocator, fixtureResolvedPeer(), .{
        .direct_disabled = true,
    });
    try std.testing.expectEqual(Outcome.relay, result.outcome);
    try std.testing.expect(result.contract.use_relay_fallback);
}

test "node orchestrator session-control path returns direct outcome" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();
    var exchange = @import("../signaling/exchange.zig").Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = @import("../signaling/rendezvous.zig").Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const discovery = @import("../discovery/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-discovery",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-discovery", .bus = &bus },
        .handler = .{ .store = &store },
    };
    const signaling = @import("../signaling/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    const relay = @import("../relay/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    const kp = try @import("libself").identity.KeyPair.fromSeed([_]u8{0xd2} ** 32);
    const did = try @import("libself").DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.240", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-orch-a", .relay_address = "relay.example.net:8443", .priority = 9 },
    };
    var record = PeerRecord{
        .node_id = @import("libself").NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const result = try connectViaSessionControl(
        std.testing.allocator,
        record,
        .{},
        discovery,
        signaling,
        relay,
    );
    try std.testing.expectEqual(Outcome.direct, result.outcome);
}

test "node orchestrator session-control path returns signaling/direct and relay outcomes" {
    var bus = @import("session_bus.zig").SessionBus.init(std.testing.allocator);
    defer bus.deinit();
    var store = @import("../discovery/store.zig").InMemoryStore.init(std.testing.allocator);
    defer store.deinit();
    var exchange = @import("../signaling/exchange.zig").Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = @import("../signaling/rendezvous.zig").Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const discovery = @import("../discovery/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-discovery",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-discovery", .bus = &bus },
        .handler = .{ .store = &store },
    };
    const signaling = @import("../signaling/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-signal",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-signal", .bus = &bus },
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };
    const relay = @import("../relay/session_transport.zig").SessionTransport{
        .client_id = "node-a",
        .server_id = "mesh-relay",
        .client = .{ .id = "node-a", .bus = &bus },
        .server = .{ .id = "mesh-relay", .bus = &bus },
    };

    const kp = try @import("libself").identity.KeyPair.fromSeed([_]u8{0xd3} ** 32);
    const did = try @import("libself").DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.241", .port = 4433, .priority = 10 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-orch-b", .relay_address = "relay.example.net:9443", .priority = 9 },
    };
    var record = PeerRecord{
        .node_id = @import("libself").NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const signaled = try connectViaSessionControl(
        std.testing.allocator,
        record,
        .{ .needs_traversal = true, .dice_available = true },
        discovery,
        signaling,
        relay,
    );
    try std.testing.expectEqual(Outcome.direct_after_signaling, signaled.outcome);

    const relayed = try connectViaSessionControl(
        std.testing.allocator,
        record,
        .{ .direct_disabled = true },
        discovery,
        signaling,
        relay,
    );
    try std.testing.expectEqual(Outcome.relay, relayed.outcome);
}

test "node orchestrator opens direct session via libfast adapter driver" {
    const Fake = struct {
        const Self = @This();
        attempts: usize = 0,
        saw_direct: bool = false,
        fn connect(ctx_ptr: *anyopaque, target: @import("libfast.zig").ConnectionTarget) MeshError!libfast_adapter.ConnectionId {
            const ctx: *Self = @ptrCast(@alignCast(ctx_ptr));
            ctx.attempts += 1;
            switch (target) {
                .direct => ctx.saw_direct = true,
                .relay => return MeshError.NotFound,
            }
            return 9001;
        }
        fn send(_: *anyopaque, _: libfast_adapter.ConnectionId, _: []const u8) MeshError!void {}
        fn recv(_: *anyopaque, _: std.mem.Allocator, _: libfast_adapter.ConnectionId) MeshError!?[]u8 {
            return null;
        }
        fn close(_: *anyopaque, _: libfast_adapter.ConnectionId) MeshError!void {}
    };

    var fake = Fake{};
    const driver = libfast_adapter.Driver{
        .ctx = &fake,
        .vtable = &.{
            .connect = Fake.connect,
            .send = Fake.send,
            .recv = Fake.recv,
            .close = Fake.close,
        },
    };

    const opened = try connectAndOpenSession(std.testing.allocator, fixtureResolvedPeer(), .{}, driver);
    try std.testing.expectEqual(Outcome.direct, opened.result.outcome);
    try std.testing.expectEqual(routing_policy.Decision.direct, opened.result.decision);
    try std.testing.expectEqual(@as(libfast_adapter.ConnectionId, 9001), opened.session.connection_id);
    try std.testing.expect(!opened.used_relay_fallback);
    try std.testing.expect(fake.saw_direct);
    try std.testing.expectEqual(@as(usize, 1), fake.attempts);
}

test "node orchestrator connectAndOpenSession falls back to relay when direct opening fails" {
    const Fake = struct {
        const Self = @This();
        attempts: usize = 0,
        saw_relay: bool = false,
        fn connect(ctx_ptr: *anyopaque, target: @import("libfast.zig").ConnectionTarget) MeshError!libfast_adapter.ConnectionId {
            const ctx: *Self = @ptrCast(@alignCast(ctx_ptr));
            ctx.attempts += 1;
            return switch (target) {
                .direct => MeshError.NotFound,
                .relay => blk: {
                    ctx.saw_relay = true;
                    break :blk 9100;
                },
            };
        }
        fn send(_: *anyopaque, _: libfast_adapter.ConnectionId, _: []const u8) MeshError!void {}
        fn recv(_: *anyopaque, _: std.mem.Allocator, _: libfast_adapter.ConnectionId) MeshError!?[]u8 {
            return null;
        }
        fn close(_: *anyopaque, _: libfast_adapter.ConnectionId) MeshError!void {}
    };

    var fake = Fake{};
    const driver = libfast_adapter.Driver{
        .ctx = &fake,
        .vtable = &.{
            .connect = Fake.connect,
            .send = Fake.send,
            .recv = Fake.recv,
            .close = Fake.close,
        },
    };

    const opened = try connectAndOpenSession(std.testing.allocator, fixtureResolvedPeer(), .{}, driver);
    try std.testing.expectEqual(Outcome.relay, opened.result.outcome);
    try std.testing.expectEqual(routing_policy.Decision.relay, opened.result.decision);
    try std.testing.expectEqual(@as(libfast_adapter.ConnectionId, 9100), opened.session.connection_id);
    try std.testing.expect(opened.used_relay_fallback);
    try std.testing.expect(fake.saw_relay);
    try std.testing.expectEqual(@as(usize, 2), fake.attempts);
}
