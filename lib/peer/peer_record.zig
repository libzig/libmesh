const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const mesh_time = @import("../common/time.zig");
const PublishedEndpoint = @import("endpoint.zig").PublishedEndpoint;
const RelayHint = @import("relay_hint.zig").RelayHint;

pub const PeerRecord = struct {
    node_id: libself.NodeId,
    did: ?[]const u8 = null,
    published_at_ms: mesh_time.TimestampMs,
    expires_at_ms: mesh_time.TimestampMs,
    endpoints: []const PublishedEndpoint,
    relay_hints: []const RelayHint,
    signature: ?libself.identity.Signature = null,

    pub fn validate(self: PeerRecord, now_ms: mesh_time.TimestampMs) MeshError!void {
        if (self.expires_at_ms <= self.published_at_ms) return MeshError.InvalidPeerRecord;
        if (mesh_time.expired(now_ms, self.expires_at_ms)) return MeshError.Expired;
        for (self.endpoints) |endpoint| try endpoint.validate();
        for (self.relay_hints) |hint| try hint.validate();
    }

    pub fn canonicalPayloadAlloc(self: PeerRecord, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        const writer = list.writer(allocator);

        const node_hex = self.node_id.toHex();
        try writer.print("node={s};", .{node_hex});
        if (self.did) |did| {
            try writer.print("did={s};", .{did});
        } else {
            try writer.writeAll("did=;");
        }
        try writer.print("published={d};expires={d};", .{ self.published_at_ms, self.expires_at_ms });

        try writer.writeAll("endpoints=");
        for (self.endpoints, 0..) |endpoint, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writer.print("{s}:{d}:{d}", .{ endpoint.host, endpoint.port, endpoint.priority });
        }
        try writer.writeAll(";relay_hints=");
        for (self.relay_hints, 0..) |hint, idx| {
            if (idx != 0) try writer.writeByte(',');
            try writer.print("{s}@{s}:{d}", .{ hint.relay_id, hint.relay_address, hint.priority });
        }
        try writer.writeByte(';');

        return list.toOwnedSlice(allocator);
    }

    pub fn sign(self: *PeerRecord, allocator: std.mem.Allocator, key_pair: libself.identity.KeyPair) !void {
        const payload = try self.canonicalPayloadAlloc(allocator);
        defer allocator.free(payload);
        self.signature = try key_pair.sign(payload);
    }

    pub fn verify(self: PeerRecord, allocator: std.mem.Allocator, public_key: libself.identity.PublicKey) !bool {
        const expected_node_id = libself.NodeId.fromPublicKey(public_key);
        if (!std.mem.eql(u8, &self.node_id.toBytes(), &expected_node_id.toBytes())) return false;

        const sig = self.signature orelse return false;
        const payload = try self.canonicalPayloadAlloc(allocator);
        defer allocator.free(payload);
        return libself.identity.verifyWithPublicKey(payload, sig, public_key);
    }
};

test "PeerRecord canonical payload is deterministic for equivalent records" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x21} ** 32);
    const node_id = libself.NodeId.fromPublicKey(key_pair.public_key);

    const endpoints = [_]PublishedEndpoint{
        .{ .host = "203.0.113.44", .port = 4433, .priority = 5 },
    };
    const relay_hints = [_]RelayHint{
        .{ .relay_id = "relay-a", .relay_address = "relay.example.net:4433", .priority = 1 },
    };

    const a = PeerRecord{
        .node_id = node_id,
        .published_at_ms = 100,
        .expires_at_ms = 200,
        .endpoints = &endpoints,
        .relay_hints = &relay_hints,
    };
    const b = a;

    const allocator = std.testing.allocator;
    const payload_a = try a.canonicalPayloadAlloc(allocator);
    defer allocator.free(payload_a);
    const payload_b = try b.canonicalPayloadAlloc(allocator);
    defer allocator.free(payload_b);

    try std.testing.expectEqualStrings(payload_a, payload_b);
}

test "PeerRecord sign and verify uses libself identity keys" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x22} ** 32);
    const node_id = libself.NodeId.fromPublicKey(key_pair.public_key);

    const endpoints = [_]PublishedEndpoint{
        .{ .host = "mesh.example", .port = 4433, .priority = 10 },
    };
    const relay_hints = [_]RelayHint{
        .{ .relay_id = "relay-b", .relay_address = "relay.example.net:7443", .priority = 2 },
    };

    var record = PeerRecord{
        .node_id = node_id,
        .did = "did:key:zexample",
        .published_at_ms = 1,
        .expires_at_ms = 999,
        .endpoints = &endpoints,
        .relay_hints = &relay_hints,
    };

    const allocator = std.testing.allocator;
    try record.sign(allocator, key_pair);
    try std.testing.expect(try record.verify(allocator, key_pair.public_key));
}

test "PeerRecord verify fails when signer key does not match node id" {
    const signer = try libself.identity.KeyPair.fromSeed([_]u8{0x23} ** 32);
    const other = try libself.identity.KeyPair.fromSeed([_]u8{0x24} ** 32);

    const endpoints = [_]PublishedEndpoint{
        .{ .host = "mesh.example", .port = 4433 },
    };
    const relay_hints = [_]RelayHint{
        .{ .relay_id = "relay-c", .relay_address = "relay.example.net:8443" },
    };

    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(other.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 20,
        .endpoints = &endpoints,
        .relay_hints = &relay_hints,
    };
    const allocator = std.testing.allocator;
    try record.sign(allocator, signer);
    try std.testing.expect(!(try record.verify(allocator, signer.public_key)));
}
