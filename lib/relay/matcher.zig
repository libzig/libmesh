const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const RelaySession = @import("session.zig").RelaySession;
const libself = @import("libself");

const Pending = struct {
    session_id: u64,
    source_node_id: libself.NodeId,
    target_node_id: libself.NodeId,
};

pub const Match = struct {
    left_session_id: u64,
    right_session_id: u64,
    left_node_id: libself.NodeId,
    right_node_id: libself.NodeId,
};

pub const Matcher = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(Pending),

    pub fn init(allocator: std.mem.Allocator) Matcher {
        return .{
            .allocator = allocator,
            .pending = .empty,
        };
    }

    pub fn deinit(self: *Matcher) void {
        self.pending.deinit(self.allocator);
    }

    pub fn register(self: *Matcher, session: RelaySession) MeshError!?Match {
        if (!session.authenticated) return MeshError.AccessDenied;

        for (self.pending.items, 0..) |item, idx| {
            if (sameNode(item.source_node_id, session.target_node_id) and
                sameNode(item.target_node_id, session.source_node_id))
            {
                _ = self.pending.swapRemove(idx);
                return Match{
                    .left_session_id = item.session_id,
                    .right_session_id = session.id,
                    .left_node_id = item.source_node_id,
                    .right_node_id = item.target_node_id,
                };
            }
        }

        self.pending.append(self.allocator, .{
            .session_id = session.id,
            .source_node_id = session.source_node_id,
            .target_node_id = session.target_node_id,
        }) catch return MeshError.BufferTooSmall;
        return null;
    }

    pub fn pendingCount(self: *const Matcher) usize {
        return self.pending.items.len;
    }
};

fn sameNode(a: libself.NodeId, b: libself.NodeId) bool {
    return std.mem.eql(u8, &a.toBytes(), &b.toBytes());
}

test "matcher returns a match when reverse pair arrives" {
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xc1} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xc2} ** 32);
    var matcher = Matcher.init(std.testing.allocator);
    defer matcher.deinit();

    const s1 = RelaySession{
        .id = 100,
        .source_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = true,
    };
    try std.testing.expect((try matcher.register(s1)) == null);
    try std.testing.expectEqual(@as(usize, 1), matcher.pendingCount());

    const s2 = RelaySession{
        .id = 101,
        .source_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .source_did = "did:key:target",
        .target_did = "did:key:source",
        .authenticated = true,
    };
    const m = (try matcher.register(s2)).?;
    try std.testing.expectEqual(@as(u64, 100), m.left_session_id);
    try std.testing.expectEqual(@as(u64, 101), m.right_session_id);
    try std.testing.expectEqual(@as(usize, 0), matcher.pendingCount());
}

test "matcher rejects unauthenticated sessions" {
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xc3} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xc4} ** 32);
    var matcher = Matcher.init(std.testing.allocator);
    defer matcher.deinit();

    const bad = RelaySession{
        .id = 111,
        .source_node_id = libself.NodeId.fromPublicKey(source.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(target.public_key),
        .source_did = "did:key:source",
        .target_did = "did:key:target",
        .authenticated = false,
    };
    try std.testing.expectError(MeshError.AccessDenied, matcher.register(bad));
}
