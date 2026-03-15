const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const mesh_time = @import("../common/time.zig");
const protocol = @import("protocol.zig");
const Store = @import("store.zig").InMemoryStore;
const peer_record = @import("../peer/peer_record.zig");

pub const Server = struct {
    store: *Store,

    pub fn handle(self: Server, allocator: std.mem.Allocator, raw_message: []const u8) MeshError![]u8 {
        const msg = try protocol.decode(raw_message);
        const node_id = parseNodeIdHex(msg.node_hex) orelse return MeshError.InvalidPeerRecord;

        return switch (msg.kind) {
            .publish => blk: {
                if (msg.payload.len == 0) return MeshError.InvalidPeerRecord;
                var parsed = try peer_record.parseWirePayload(allocator, msg.payload);
                defer parsed.deinit();
                if (!std.mem.eql(u8, msg.node_hex, &parsed.record.node_id.toHex())) return MeshError.InvalidPeerRecord;
                const signer_key = try signerKeyFromDid(allocator, parsed.record.did);
                try requirePublishTimeWithinSkew(parsed.record.published_at_ms);
                try self.store.publish(parsed.record, signer_key, parsed.record.published_at_ms);
                break :blk protocol.encode(allocator, .{
                    .kind = .response,
                    .correlation_id = msg.correlation_id,
                    .node_hex = msg.node_hex,
                    .payload = "ok",
                });
            },
            .lookup => blk: {
                if (msg.payload.len != 0) return MeshError.InvalidPeerRecord;
                const payload = if (self.store.lookup(node_id)) |record| p: {
                    const wire = record.wirePayloadAlloc(allocator) catch return MeshError.BufferTooSmall;
                    break :p wire;
                } else |err| p: {
                    if (err == MeshError.NotFound) break :p allocator.dupe(u8, "not_found") catch return MeshError.BufferTooSmall;
                    return err;
                };
                defer allocator.free(payload);

                break :blk protocol.encode(allocator, .{
                    .kind = .response,
                    .correlation_id = msg.correlation_id,
                    .node_hex = msg.node_hex,
                    .payload = payload,
                });
            },
            .refresh => blk: {
                if (msg.payload.len == 0) return MeshError.InvalidPeerRecord;
                var parsed = try peer_record.parseWirePayload(allocator, msg.payload);
                defer parsed.deinit();
                if (!std.mem.eql(u8, msg.node_hex, &parsed.record.node_id.toHex())) return MeshError.InvalidPeerRecord;
                const signer_key = try signerKeyFromDid(allocator, parsed.record.did);
                try requirePublishTimeWithinSkew(parsed.record.published_at_ms);
                try self.store.refresh(parsed.record, signer_key, parsed.record.published_at_ms);
                break :blk protocol.encode(allocator, .{
                    .kind = .response,
                    .correlation_id = msg.correlation_id,
                    .node_hex = msg.node_hex,
                    .payload = "ok",
                });
            },
            .withdraw => blk: {
                if (msg.payload.len != 0) return MeshError.InvalidPeerRecord;
                _ = self.store.withdraw(node_id) catch |err| if (err != MeshError.NotFound) return err;
                break :blk protocol.encode(allocator, .{
                    .kind = .response,
                    .correlation_id = msg.correlation_id,
                    .node_hex = msg.node_hex,
                    .payload = "ok",
                });
            },
            else => MeshError.InvalidPeerRecord,
        };
    }
};

const max_future_publish_skew_ms: u64 = 5 * 60 * 1000;

fn requirePublishTimeWithinSkew(published_at_ms: u64) MeshError!void {
    const now = mesh_time.nowMs();
    if (published_at_ms > now + max_future_publish_skew_ms) return MeshError.InvalidPeerRecord;
}

fn signerKeyFromDid(allocator: std.mem.Allocator, did: ?[]const u8) MeshError!libself.identity.PublicKey {
    const did_text = did orelse return MeshError.AccessDenied;
    const parsed = libself.DidKey.parse(allocator, did_text) catch return MeshError.AccessDenied;
    return parsed.public_key;
}

fn parseNodeIdHex(hex: []const u8) ?libself.NodeId {
    if (hex.len != 64) return null;
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&bytes, hex) catch return null;
    return libself.NodeId{ .bytes = bytes };
}

test "discovery server handles lookup and returns response payload" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd2} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.30", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-server", .relay_address = "relay.example.net:4433" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .published_at_ms = 1,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    try store.publish(record, kp.public_key, 5);

    const lookup_msg = try @import("client.zig").buildLookup(std.testing.allocator, 9, record.node_id);
    defer std.testing.allocator.free(lookup_msg);
    const response_raw = try server.handle(std.testing.allocator, lookup_msg);
    defer std.testing.allocator.free(response_raw);

    const response = try protocol.decode(response_raw);
    try std.testing.expectEqual(protocol.MessageKind.response, response.kind);
    try std.testing.expect(std.mem.indexOf(u8, response.payload, "node=") != null);
}

test "discovery server handles withdraw request" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd3} ** 32);
    const node_id = libself.NodeId.fromPublicKey(kp.public_key);

    const withdraw_msg = try @import("client.zig").buildWithdraw(std.testing.allocator, 10, node_id);
    defer std.testing.allocator.free(withdraw_msg);
    const response_raw = try server.handle(std.testing.allocator, withdraw_msg);
    defer std.testing.allocator.free(response_raw);

    const response = try protocol.decode(response_raw);
    try std.testing.expectEqualStrings("ok", response.payload);
}

test "discovery server handles publish and refresh through signed wire payloads" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd6} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.77", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-publish", .relay_address = "relay.example.net:4433" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 5,
        .expires_at_ms = 80,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const publish_msg = try @import("client.zig").buildPublish(std.testing.allocator, 12, record);
    defer std.testing.allocator.free(publish_msg);
    const publish_rsp = try server.handle(std.testing.allocator, publish_msg);
    defer std.testing.allocator.free(publish_rsp);
    try std.testing.expectEqualStrings("ok", (try protocol.decode(publish_rsp)).payload);

    var refreshed = record;
    refreshed.expires_at_ms = 120;
    try refreshed.sign(std.testing.allocator, kp);
    const refresh_msg = try @import("client.zig").buildRefresh(std.testing.allocator, 13, refreshed);
    defer std.testing.allocator.free(refresh_msg);
    const refresh_rsp = try server.handle(std.testing.allocator, refresh_msg);
    defer std.testing.allocator.free(refresh_rsp);
    try std.testing.expectEqualStrings("ok", (try protocol.decode(refresh_rsp)).payload);

    const lookup_msg = try @import("client.zig").buildLookup(std.testing.allocator, 14, refreshed.node_id);
    defer std.testing.allocator.free(lookup_msg);
    const lookup_rsp = try server.handle(std.testing.allocator, lookup_msg);
    defer std.testing.allocator.free(lookup_rsp);
    var parsed_lookup = try @import("client.zig").parseLookupResponse(std.testing.allocator, lookup_rsp);
    defer parsed_lookup.deinit();
    try std.testing.expectEqual(@as(u64, 120), parsed_lookup.record.expires_at_ms);
    try std.testing.expect(try parsed_lookup.record.verify(std.testing.allocator, kp.public_key));
}

test "discovery server rejects publish records dated in the future" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd7} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.78", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-future", .relay_address = "relay.example.net:5443" },
    };
    const future_publish = mesh_time.nowMs() + max_future_publish_skew_ms + 60_000;
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = future_publish,
        .expires_at_ms = future_publish + 5_000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const publish_msg = try @import("client.zig").buildPublish(std.testing.allocator, 15, record);
    defer std.testing.allocator.free(publish_msg);
    try std.testing.expectError(MeshError.InvalidPeerRecord, server.handle(std.testing.allocator, publish_msg));
}

test "discovery server rejects publish payload when node hex does not match signed record node id" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };

    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd8} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.79", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-node-mismatch", .relay_address = "relay.example.net:8443" },
    };
    var record = @import("../peer/peer_record.zig").PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 5,
        .expires_at_ms = 500,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const publish_msg = try @import("client.zig").buildPublish(std.testing.allocator, 16, record);
    defer std.testing.allocator.free(publish_msg);
    const decoded = try protocol.decode(publish_msg);
    const tampered = try protocol.encode(std.testing.allocator, .{
        .kind = .publish,
        .correlation_id = decoded.correlation_id,
        .node_hex = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        .payload = decoded.payload,
    });
    defer std.testing.allocator.free(tampered);

    try std.testing.expectError(MeshError.InvalidPeerRecord, server.handle(std.testing.allocator, tampered));
}

test "discovery server enforces request payload semantics by method kind" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    const server = Server{ .store = &store };
    const node_hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    const bad_lookup = try protocol.encode(std.testing.allocator, .{
        .kind = .lookup,
        .correlation_id = 17,
        .node_hex = node_hex,
        .payload = "unexpected",
    });
    defer std.testing.allocator.free(bad_lookup);
    try std.testing.expectError(MeshError.InvalidPeerRecord, server.handle(std.testing.allocator, bad_lookup));

    const bad_withdraw = try protocol.encode(std.testing.allocator, .{
        .kind = .withdraw,
        .correlation_id = 18,
        .node_hex = node_hex,
        .payload = "unexpected",
    });
    defer std.testing.allocator.free(bad_withdraw);
    try std.testing.expectError(MeshError.InvalidPeerRecord, server.handle(std.testing.allocator, bad_withdraw));

    const bad_publish = try protocol.encode(std.testing.allocator, .{
        .kind = .publish,
        .correlation_id = 19,
        .node_hex = node_hex,
        .payload = "",
    });
    defer std.testing.allocator.free(bad_publish);
    try std.testing.expectError(MeshError.InvalidPeerRecord, server.handle(std.testing.allocator, bad_publish));
}
