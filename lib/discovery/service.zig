const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;
const InMemoryStore = @import("store.zig").InMemoryStore;

pub const Service = struct {
    store: *InMemoryStore,
    signer_public_key: libself.identity.PublicKey,

    pub fn publish(self: Service, record: PeerRecord, now_ms: u64) MeshError!void {
        try self.store.publish(record, self.signer_public_key, now_ms);
    }

    pub fn lookup(self: Service, node_id: libself.NodeId) MeshError!PeerRecord {
        return self.store.lookup(node_id);
    }

    pub fn lookupAt(self: Service, node_id: libself.NodeId, now_ms: u64) MeshError!PeerRecord {
        return self.store.lookupAt(node_id, now_ms);
    }

    pub fn refresh(self: Service, record: PeerRecord, now_ms: u64) MeshError!void {
        try self.store.refresh(record, self.signer_public_key, now_ms);
    }

    pub fn withdraw(self: Service, node_id: libself.NodeId) MeshError!void {
        try self.store.withdraw(node_id);
    }

    pub fn expire(self: Service, now_ms: u64) usize {
        return self.store.pruneExpired(now_ms);
    }
};

test "discovery service provides publish lookup refresh withdraw lifecycle" {
    var store = InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x44} ** 32);
    const service = Service{
        .store = &store,
        .signer_public_key = key_pair.public_key,
    };

    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.10", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-service", .relay_address = "relay.example.net:4433" },
    };

    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 100,
        .expires_at_ms = 200,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try service.publish(record, 150);

    const loaded = try service.lookup(record.node_id);
    try std.testing.expectEqual(@as(u64, 200), loaded.expires_at_ms);

    var refreshed = loaded;
    refreshed.expires_at_ms = 300;
    try refreshed.sign(std.testing.allocator, key_pair);
    try service.refresh(refreshed, 220);
    try std.testing.expectEqual(@as(u64, 300), (try service.lookup(record.node_id)).expires_at_ms);

    try service.withdraw(record.node_id);
    try std.testing.expectError(MeshError.NotFound, service.lookup(record.node_id));
}

test "discovery service lookupAt and expire enforce freshness checks" {
    var store = InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x45} ** 32);
    const service = Service{
        .store = &store,
        .signer_public_key = key_pair.public_key,
    };
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "198.51.100.11", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-service-expire", .relay_address = "relay.example.net:5443" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 20,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try service.publish(record, 11);

    _ = try service.lookupAt(record.node_id, 20);
    try std.testing.expectError(MeshError.Expired, service.lookupAt(record.node_id, 21));
    try std.testing.expectEqual(@as(usize, 1), service.expire(21));
    try std.testing.expectError(MeshError.NotFound, service.lookup(record.node_id));
}
