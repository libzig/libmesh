const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const PeerRecord = @import("../peer/peer_record.zig").PeerRecord;

const Entry = struct {
    node_id: libself.NodeId,
    record: PeerRecord,
};

pub const InMemoryStore = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry),

    pub fn init(allocator: std.mem.Allocator) InMemoryStore {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *InMemoryStore) void {
        for (self.entries.items) |entry| {
            self.freeRecord(entry.record);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn publish(self: *InMemoryStore, record: PeerRecord, signer_public_key: libself.identity.PublicKey, now_ms: u64) MeshError!void {
        try record.validate(now_ms);
        if (!(record.verify(self.allocator, signer_public_key) catch false)) return MeshError.InvalidSignature;
        const owned = try self.cloneRecord(record);

        if (self.findIndex(record.node_id)) |idx| {
            self.freeRecord(self.entries.items[idx].record);
            self.entries.items[idx].record = owned;
            return;
        }

        self.entries.append(self.allocator, .{
            .node_id = record.node_id,
            .record = owned,
        }) catch return MeshError.BufferTooSmall;
    }

    pub fn lookup(self: *const InMemoryStore, node_id: libself.NodeId) MeshError!PeerRecord {
        const idx = self.findIndex(node_id) orelse return MeshError.NotFound;
        return self.entries.items[idx].record;
    }

    pub fn refresh(self: *InMemoryStore, record: PeerRecord, signer_public_key: libself.identity.PublicKey, now_ms: u64) MeshError!void {
        const idx = self.findIndex(record.node_id) orelse return MeshError.NotFound;
        try record.validate(now_ms);
        if (!(record.verify(self.allocator, signer_public_key) catch false)) return MeshError.InvalidSignature;
        const owned = try self.cloneRecord(record);
        self.freeRecord(self.entries.items[idx].record);
        self.entries.items[idx].record = owned;
    }

    pub fn withdraw(self: *InMemoryStore, node_id: libself.NodeId) MeshError!void {
        const idx = self.findIndex(node_id) orelse return MeshError.NotFound;
        const removed = self.entries.swapRemove(idx);
        self.freeRecord(removed.record);
    }

    fn findIndex(self: *const InMemoryStore, node_id: libself.NodeId) ?usize {
        for (self.entries.items, 0..) |entry, idx| {
            if (std.mem.eql(u8, &entry.node_id.toBytes(), &node_id.toBytes())) return idx;
        }
        return null;
    }

    fn cloneRecord(self: *InMemoryStore, source: PeerRecord) MeshError!PeerRecord {
        const did_owned = if (source.did) |did| self.allocator.dupe(u8, did) catch return MeshError.BufferTooSmall else null;
        errdefer if (did_owned) |did| self.allocator.free(did);

        var endpoints_owned = self.allocator.alloc(@import("../peer/endpoint.zig").PublishedEndpoint, source.endpoints.len) catch return MeshError.BufferTooSmall;
        var endpoint_count: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < endpoint_count) : (i += 1) {
                self.allocator.free(endpoints_owned[i].host);
                if (endpoints_owned[i].alpn) |alpn| self.allocator.free(alpn);
            }
            self.allocator.free(endpoints_owned);
        }
        for (source.endpoints, 0..) |endpoint, idx| {
            endpoints_owned[idx] = endpoint;
            endpoints_owned[idx].host = self.allocator.dupe(u8, endpoint.host) catch return MeshError.BufferTooSmall;
            endpoints_owned[idx].alpn = if (endpoint.alpn) |alpn| self.allocator.dupe(u8, alpn) catch return MeshError.BufferTooSmall else null;
            endpoint_count += 1;
        }

        var hints_owned = self.allocator.alloc(@import("../peer/relay_hint.zig").RelayHint, source.relay_hints.len) catch return MeshError.BufferTooSmall;
        var hint_count: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < hint_count) : (i += 1) {
                self.allocator.free(hints_owned[i].relay_id);
                self.allocator.free(hints_owned[i].relay_address);
                self.allocator.free(hints_owned[i].relay_alpn);
            }
            self.allocator.free(hints_owned);
        }
        for (source.relay_hints, 0..) |hint, idx| {
            hints_owned[idx] = hint;
            hints_owned[idx].relay_id = self.allocator.dupe(u8, hint.relay_id) catch return MeshError.BufferTooSmall;
            hints_owned[idx].relay_address = self.allocator.dupe(u8, hint.relay_address) catch return MeshError.BufferTooSmall;
            hints_owned[idx].relay_alpn = self.allocator.dupe(u8, hint.relay_alpn) catch return MeshError.BufferTooSmall;
            hint_count += 1;
        }

        return .{
            .node_id = source.node_id,
            .did = did_owned,
            .published_at_ms = source.published_at_ms,
            .expires_at_ms = source.expires_at_ms,
            .endpoints = endpoints_owned,
            .relay_hints = hints_owned,
            .signature = source.signature,
        };
    }

    fn freeRecord(self: *InMemoryStore, record: PeerRecord) void {
        if (record.did) |did| self.allocator.free(did);

        for (record.endpoints) |endpoint| {
            self.allocator.free(endpoint.host);
            if (endpoint.alpn) |alpn| self.allocator.free(alpn);
        }
        self.allocator.free(record.endpoints);

        for (record.relay_hints) |hint| {
            self.allocator.free(hint.relay_id);
            self.allocator.free(hint.relay_address);
            self.allocator.free(hint.relay_alpn);
        }
        self.allocator.free(record.relay_hints);
    }
};

test "InMemoryStore publish and lookup returns verified peer record" {
    var store = InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x31} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.70", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-d", .relay_address = "relay.example.net:4433" },
    };

    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try store.publish(record, key_pair.public_key, 20);

    const loaded = try store.lookup(record.node_id);
    try std.testing.expect(try loaded.verify(std.testing.allocator, key_pair.public_key));
}

test "InMemoryStore rejects unsigned or invalid signatures" {
    var store = InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x32} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "mesh.example", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-e", .relay_address = "relay.example.net:5443" },
    };

    const record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try std.testing.expectError(MeshError.InvalidSignature, store.publish(record, key_pair.public_key, 20));
}

test "InMemoryStore refresh and withdraw enforce lifecycle" {
    var store = InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x33} ** 32);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.90", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-f", .relay_address = "relay.example.net:6443" },
    };

    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try store.publish(record, key_pair.public_key, 20);

    var refreshed = record;
    refreshed.expires_at_ms = 200;
    try refreshed.sign(std.testing.allocator, key_pair);
    try store.refresh(refreshed, key_pair.public_key, 30);
    try std.testing.expectEqual(@as(u64, 200), (try store.lookup(record.node_id)).expires_at_ms);

    try store.withdraw(record.node_id);
    try std.testing.expectError(MeshError.NotFound, store.lookup(record.node_id));
}
