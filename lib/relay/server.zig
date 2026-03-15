const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const Matcher = @import("matcher.zig").Matcher;
const Match = @import("matcher.zig").Match;
const Policy = @import("policy.zig").Policy;
const RelaySession = @import("session.zig").RelaySession;
const session_api = @import("session.zig");

const ActiveSession = struct {
    id: u64,
    source_node_id: libself.NodeId,
    target_node_id: libself.NodeId,
    authenticated: bool,
};

pub const OpenResult = struct {
    session: RelaySession,
    matched: ?Match,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    policy: Policy,
    matcher: *Matcher,
    sessions: std.ArrayList(ActiveSession),

    pub fn init(allocator: std.mem.Allocator, matcher: *Matcher, policy: Policy) Server {
        return .{
            .allocator = allocator,
            .policy = policy,
            .matcher = matcher,
            .sessions = .empty,
        };
    }

    pub fn deinit(self: *Server) void {
        self.sessions.deinit(self.allocator);
    }

    pub fn open(
        self: *Server,
        id: u64,
        source_public_key: libself.identity.PublicKey,
        source_did: []const u8,
        target_public_key: libself.identity.PublicKey,
        target_did: []const u8,
    ) MeshError!OpenResult {
        const relay_session = try session_api.openAuthenticated(
            id,
            source_public_key,
            source_did,
            target_public_key,
            target_did,
        );
        if (!self.policy.allow(self.sessions.items.len, relay_session)) return MeshError.AccessDenied;

        const matched = try self.matcher.register(relay_session);

        self.sessions.append(self.allocator, .{
            .id = relay_session.id,
            .source_node_id = relay_session.source_node_id,
            .target_node_id = relay_session.target_node_id,
            .authenticated = relay_session.authenticated,
        }) catch return MeshError.BufferTooSmall;

        return .{
            .session = relay_session,
            .matched = matched,
        };
    }

    pub fn close(self: *Server, session_id: u64) bool {
        for (self.sessions.items, 0..) |active, idx| {
            if (active.id == session_id) {
                _ = self.sessions.swapRemove(idx);
                _ = self.matcher.removePendingSession(session_id);
                return true;
            }
        }
        return false;
    }

    pub fn activeCount(self: *const Server) usize {
        return self.sessions.items.len;
    }
};

test "relay server opens authenticated session and matches reverse peer" {
    var matcher = Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 8,
        .require_authenticated = true,
    });
    defer server.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xb1} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xb2} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    const first = try server.open(1, source.public_key, source_did, target.public_key, target_did);
    try std.testing.expect(first.matched == null);
    try std.testing.expectEqual(@as(usize, 1), server.activeCount());

    const second = try server.open(2, target.public_key, target_did, source.public_key, source_did);
    try std.testing.expect(second.matched != null);
    try std.testing.expectEqual(@as(usize, 2), server.activeCount());
}

test "relay server rejects invalid did/public key combinations" {
    var matcher = Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 1,
        .require_authenticated = true,
    });
    defer server.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xb3} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xb4} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    try std.testing.expectError(
        MeshError.AccessDenied,
        server.open(5, source.public_key, source_did, target.public_key, source_did),
    );
}

test "relay server close removes active session" {
    var matcher = Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 4,
        .require_authenticated = true,
    });
    defer server.deinit();

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xb5} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xb6} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    _ = try server.open(7, source.public_key, source_did, target.public_key, target_did);
    try std.testing.expectEqual(@as(usize, 1), matcher.pendingCount());
    try std.testing.expect(server.close(7));
    try std.testing.expectEqual(@as(usize, 0), matcher.pendingCount());
    try std.testing.expectEqual(@as(usize, 0), server.activeCount());
    try std.testing.expect(!server.close(7));
}
