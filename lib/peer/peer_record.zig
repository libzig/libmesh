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
        const sorted_endpoints = try allocator.alloc(PublishedEndpoint, self.endpoints.len);
        defer allocator.free(sorted_endpoints);
        @memcpy(sorted_endpoints, self.endpoints);
        std.mem.sort(PublishedEndpoint, sorted_endpoints, {}, struct {
            fn lessThan(_: void, a: PublishedEndpoint, b: PublishedEndpoint) bool {
                const host_order = std.mem.order(u8, a.host, b.host);
                if (host_order != .eq) return host_order == .lt;
                if (a.port != b.port) return a.port < b.port;
                return a.priority > b.priority;
            }
        }.lessThan);

        const node_hex = self.node_id.toHex();
        try writer.print("node={s};", .{node_hex});
        if (self.did) |did| {
            try writer.print("did={s};", .{did});
        } else {
            try writer.writeAll("did=;");
        }
        try writer.print("published={d};expires={d};", .{ self.published_at_ms, self.expires_at_ms });

        try writer.writeAll("endpoints=");
        for (sorted_endpoints, 0..) |endpoint, idx| {
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

    pub fn wirePayloadAlloc(self: PeerRecord, allocator: std.mem.Allocator) ![]u8 {
        const canonical = try self.canonicalPayloadAlloc(allocator);
        defer allocator.free(canonical);

        var list = std.ArrayList(u8).empty;
        defer list.deinit(allocator);
        try list.appendSlice(allocator, canonical);
        const writer = list.writer(allocator);
        if (self.signature) |sig| {
            const sig_hex = std.fmt.bytesToHex(sig, .lower);
            try writer.print("sig={s};", .{&sig_hex});
        } else {
            try writer.writeAll("sig=;");
        }
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

pub const ParsedPeerRecord = struct {
    arena: std.heap.ArenaAllocator,
    record: PeerRecord,

    pub fn deinit(self: *ParsedPeerRecord) void {
        self.arena.deinit();
    }
};

pub fn parseWirePayload(allocator: std.mem.Allocator, raw: []const u8) MeshError!ParsedPeerRecord {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    var node_hex: ?[]const u8 = null;
    var did: ?[]const u8 = null;
    var published_at_ms: ?mesh_time.TimestampMs = null;
    var expires_at_ms: ?mesh_time.TimestampMs = null;
    var endpoints_text: []const u8 = "";
    var relay_hints_text: []const u8 = "";
    var signature: ?libself.identity.Signature = null;

    var sections = std.mem.splitScalar(u8, raw, ';');
    while (sections.next()) |section| {
        if (section.len == 0) continue;
        const eq_idx = std.mem.indexOfScalar(u8, section, '=') orelse return MeshError.InvalidPeerRecord;
        const key = section[0..eq_idx];
        const value = section[eq_idx + 1 ..];

        if (std.mem.eql(u8, key, "node")) {
            node_hex = a.dupe(u8, value) catch return MeshError.BufferTooSmall;
        } else if (std.mem.eql(u8, key, "did")) {
            if (value.len != 0) did = a.dupe(u8, value) catch return MeshError.BufferTooSmall;
        } else if (std.mem.eql(u8, key, "published")) {
            published_at_ms = std.fmt.parseInt(mesh_time.TimestampMs, value, 10) catch return MeshError.InvalidPeerRecord;
        } else if (std.mem.eql(u8, key, "expires")) {
            expires_at_ms = std.fmt.parseInt(mesh_time.TimestampMs, value, 10) catch return MeshError.InvalidPeerRecord;
        } else if (std.mem.eql(u8, key, "endpoints")) {
            endpoints_text = a.dupe(u8, value) catch return MeshError.BufferTooSmall;
        } else if (std.mem.eql(u8, key, "relay_hints")) {
            relay_hints_text = a.dupe(u8, value) catch return MeshError.BufferTooSmall;
        } else if (std.mem.eql(u8, key, "sig")) {
            if (value.len == 0) {
                signature = null;
            } else {
                if (value.len != 128) return MeshError.InvalidSignature;
                var sig: libself.identity.Signature = undefined;
                _ = std.fmt.hexToBytes(&sig, value) catch return MeshError.InvalidSignature;
                signature = sig;
            }
        }
    }

    const node_value = node_hex orelse return MeshError.InvalidPeerRecord;
    if (node_value.len != 64) return MeshError.InvalidPeerRecord;
    var node_bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&node_bytes, node_value) catch return MeshError.InvalidPeerRecord;

    const endpoints = try parseEndpoints(a, endpoints_text);
    const relay_hints = try parseRelayHints(a, relay_hints_text);

    return .{
        .arena = arena,
        .record = .{
            .node_id = libself.NodeId{ .bytes = node_bytes },
            .did = did,
            .published_at_ms = published_at_ms orelse return MeshError.InvalidPeerRecord,
            .expires_at_ms = expires_at_ms orelse return MeshError.InvalidPeerRecord,
            .endpoints = endpoints,
            .relay_hints = relay_hints,
            .signature = signature,
        },
    };
}

fn parseEndpoints(allocator: std.mem.Allocator, text: []const u8) MeshError![]PublishedEndpoint {
    if (text.len == 0) return allocator.alloc(PublishedEndpoint, 0) catch MeshError.BufferTooSmall;

    var out = std.ArrayList(PublishedEndpoint).empty;
    errdefer out.deinit(allocator);
    var entries = std.mem.splitScalar(u8, text, ',');
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        const right_colon = std.mem.lastIndexOfScalar(u8, entry, ':') orelse return MeshError.InvalidEndpoint;
        const left_colon = std.mem.lastIndexOfScalar(u8, entry[0..right_colon], ':') orelse return MeshError.InvalidEndpoint;
        const host = entry[0..left_colon];
        const port_text = entry[left_colon + 1 .. right_colon];
        const priority_text = entry[right_colon + 1 ..];

        const host_owned = allocator.dupe(u8, host) catch return MeshError.BufferTooSmall;
        const port = std.fmt.parseInt(u16, port_text, 10) catch return MeshError.InvalidEndpoint;
        const priority = std.fmt.parseInt(i16, priority_text, 10) catch return MeshError.InvalidEndpoint;
        out.append(allocator, .{
            .host = host_owned,
            .port = port,
            .priority = priority,
        }) catch return MeshError.BufferTooSmall;
    }
    return out.toOwnedSlice(allocator) catch MeshError.BufferTooSmall;
}

fn parseRelayHints(allocator: std.mem.Allocator, text: []const u8) MeshError![]RelayHint {
    if (text.len == 0) return allocator.alloc(RelayHint, 0) catch MeshError.BufferTooSmall;

    var out = std.ArrayList(RelayHint).empty;
    errdefer out.deinit(allocator);
    var entries = std.mem.splitScalar(u8, text, ',');
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        const at_idx = std.mem.indexOfScalar(u8, entry, '@') orelse return MeshError.InvalidRelayHint;
        const right_colon = std.mem.lastIndexOfScalar(u8, entry, ':') orelse return MeshError.InvalidRelayHint;
        if (right_colon <= at_idx) return MeshError.InvalidRelayHint;

        const relay_id = entry[0..at_idx];
        const relay_address = entry[at_idx + 1 .. right_colon];
        const priority_text = entry[right_colon + 1 ..];
        const relay_id_owned = allocator.dupe(u8, relay_id) catch return MeshError.BufferTooSmall;
        const relay_address_owned = allocator.dupe(u8, relay_address) catch return MeshError.BufferTooSmall;
        const priority = std.fmt.parseInt(i16, priority_text, 10) catch return MeshError.InvalidRelayHint;

        out.append(allocator, .{
            .relay_id = relay_id_owned,
            .relay_address = relay_address_owned,
            .priority = priority,
        }) catch return MeshError.BufferTooSmall;
    }
    return out.toOwnedSlice(allocator) catch MeshError.BufferTooSmall;
}

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

test "PeerRecord canonical payload normalizes endpoint ordering" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x2a} ** 32);
    const node_id = libself.NodeId.fromPublicKey(key_pair.public_key);
    const relay_hints = [_]RelayHint{
        .{ .relay_id = "relay-same", .relay_address = "relay.example.net:4433", .priority = 1 },
    };

    const ordered = [_]PublishedEndpoint{
        .{ .host = "198.51.100.10", .port = 4433, .priority = 1 },
        .{ .host = "198.51.100.20", .port = 4433, .priority = 5 },
    };
    const reversed = [_]PublishedEndpoint{
        .{ .host = "198.51.100.20", .port = 4433, .priority = 5 },
        .{ .host = "198.51.100.10", .port = 4433, .priority = 1 },
    };

    const a = PeerRecord{
        .node_id = node_id,
        .published_at_ms = 1,
        .expires_at_ms = 10,
        .endpoints = &ordered,
        .relay_hints = &relay_hints,
    };
    const b = PeerRecord{
        .node_id = node_id,
        .published_at_ms = 1,
        .expires_at_ms = 10,
        .endpoints = &reversed,
        .relay_hints = &relay_hints,
    };

    const payload_a = try a.canonicalPayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(payload_a);
    const payload_b = try b.canonicalPayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(payload_b);
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

test "PeerRecord wire payload roundtrip preserves signed record" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x25} ** 32);
    const endpoints = [_]PublishedEndpoint{
        .{ .host = "203.0.113.200", .port = 4433, .priority = 3 },
    };
    const relay_hints = [_]RelayHint{
        .{ .relay_id = "relay-wire", .relay_address = "relay.example.net:9443", .priority = 2 },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(key_pair.public_key),
        .did = "did:key:zwire",
        .published_at_ms = 50,
        .expires_at_ms = 500,
        .endpoints = &endpoints,
        .relay_hints = &relay_hints,
    };
    try record.sign(std.testing.allocator, key_pair);

    const wire = try record.wirePayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(wire);

    var parsed = try parseWirePayload(std.testing.allocator, wire);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("did:key:zwire", parsed.record.did.?);
    try std.testing.expect(parsed.record.signature != null);
    try std.testing.expect(try parsed.record.verify(std.testing.allocator, key_pair.public_key));
}
