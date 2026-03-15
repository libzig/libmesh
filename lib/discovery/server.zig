const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const protocol = @import("protocol.zig");
const Store = @import("store.zig").InMemoryStore;

pub const Server = struct {
    store: *Store,

    pub fn handle(self: Server, allocator: std.mem.Allocator, raw_message: []const u8) MeshError![]u8 {
        const msg = try protocol.decode(raw_message);
        const node_id = parseNodeIdHex(msg.node_hex) orelse return MeshError.InvalidPeerRecord;

        return switch (msg.kind) {
            .lookup => blk: {
                const payload = if (self.store.lookup(node_id)) |record| p: {
                    const canonical = record.canonicalPayloadAlloc(allocator) catch return MeshError.BufferTooSmall;
                    break :p canonical;
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
            .withdraw => blk: {
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
