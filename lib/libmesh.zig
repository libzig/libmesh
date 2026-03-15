const libself = @import("libself");
const libfast = @import("libfast");

pub fn hello() []const u8 {
    return "hello from libmesh";
}

pub const Foundation = struct {
    pub const NodeId = libself.NodeId;
    pub const KeyPair = libself.identity.KeyPair;
    pub const DidKey = libself.DidKey;
};

pub const common = struct {
    pub const errors = @import("common/error.zig");
    pub const time = @import("common/time.zig");
    pub const version = @import("common/version.zig");
    pub const caps = @import("common/caps.zig");
};

pub const peer = struct {
    pub const endpoint = @import("peer/endpoint.zig");
    pub const peer_record = @import("peer/peer_record.zig");
    pub const relay_hint = @import("peer/relay_hint.zig");
};

pub const discovery = struct {
    pub const store = @import("discovery/store.zig");
};

pub const signaling = struct {
    pub const protocol = @import("signaling/protocol.zig");
    pub const rendezvous = @import("signaling/rendezvous.zig");
};

test "libmesh foundation imports libself and libfast" {
    const std = @import("std");
    try std.testing.expectEqualStrings("hello from libmesh", hello());
    try std.testing.expect(libfast.version.len > 0);

    const key_pair = try Foundation.KeyPair.fromSeed([_]u8{0x11} ** 32);
    const node_id = Foundation.NodeId.fromPublicKey(key_pair.public_key);
    try std.testing.expect(node_id.toHex().len == 64);

    const allocator = std.testing.allocator;
    const did = try Foundation.DidKey.fromKeyPair(key_pair).encode(allocator);
    defer allocator.free(did);
    try std.testing.expect(std.mem.startsWith(u8, did, "did:key:"));

    _ = common.errors;
    _ = common.time;
    _ = common.version;
    _ = common.caps;
    _ = peer.endpoint;
    _ = peer.peer_record;
    _ = peer.relay_hint;
    _ = discovery.store;
    _ = signaling.protocol;
    _ = signaling.rendezvous;
}
