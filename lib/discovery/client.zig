const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const protocol = @import("protocol.zig");
const peer_record = @import("../peer/peer_record.zig");
const PeerRecord = peer_record.PeerRecord;
pub const ParsedPeerRecord = peer_record.ParsedPeerRecord;

pub fn buildLookup(allocator: std.mem.Allocator, correlation_id: u64, node_id: libself.NodeId) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .lookup,
        .correlation_id = correlation_id,
        .node_hex = &node_id.toHex(),
        .payload = "",
    });
}

pub fn buildWithdraw(allocator: std.mem.Allocator, correlation_id: u64, node_id: libself.NodeId) MeshError![]u8 {
    return protocol.encode(allocator, .{
        .kind = .withdraw,
        .correlation_id = correlation_id,
        .node_hex = &node_id.toHex(),
        .payload = "",
    });
}

pub fn buildPublish(allocator: std.mem.Allocator, correlation_id: u64, record: PeerRecord) MeshError![]u8 {
    const payload = record.wirePayloadAlloc(allocator) catch return MeshError.BufferTooSmall;
    defer allocator.free(payload);
    return protocol.encode(allocator, .{
        .kind = .publish,
        .correlation_id = correlation_id,
        .node_hex = &record.node_id.toHex(),
        .payload = payload,
    });
}

pub fn buildRefresh(allocator: std.mem.Allocator, correlation_id: u64, record: PeerRecord) MeshError![]u8 {
    const payload = record.wirePayloadAlloc(allocator) catch return MeshError.BufferTooSmall;
    defer allocator.free(payload);
    return protocol.encode(allocator, .{
        .kind = .refresh,
        .correlation_id = correlation_id,
        .node_hex = &record.node_id.toHex(),
        .payload = payload,
    });
}

pub fn parseLookupResponse(allocator: std.mem.Allocator, raw_response: []const u8) MeshError!ParsedPeerRecord {
    const response = try protocol.decode(raw_response);
    if (response.kind != .response) return MeshError.InvalidPeerRecord;
    if (std.mem.eql(u8, response.payload, "not_found")) return MeshError.NotFound;
    var parsed = try peer_record.parseWirePayload(allocator, response.payload);
    if (!std.mem.eql(u8, response.node_hex, &parsed.record.node_id.toHex())) {
        parsed.deinit();
        return MeshError.InvalidPeerRecord;
    }
    return parsed;
}

pub fn parseLookupResponseForCorrelation(
    allocator: std.mem.Allocator,
    expected_correlation_id: u64,
    raw_response: []const u8,
) MeshError!ParsedPeerRecord {
    const response = try protocol.decode(raw_response);
    if (response.correlation_id != expected_correlation_id) return MeshError.InvalidPeerRecord;
    return parseLookupResponse(allocator, raw_response);
}

test "discovery client builds lookup message with node hex id" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd1} ** 32);
    const node_id = libself.NodeId.fromPublicKey(kp.public_key);
    const encoded = try buildLookup(std.testing.allocator, 1, node_id);
    defer std.testing.allocator.free(encoded);

    const decoded = try protocol.decode(encoded);
    try std.testing.expectEqual(protocol.MessageKind.lookup, decoded.kind);
    try std.testing.expectEqualStrings(&node_id.toHex(), decoded.node_hex);
}

test "discovery client builds publish and refresh messages with wire record payloads" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd4} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.50", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-client", .relay_address = "relay.example.net:4433" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 1,
        .expires_at_ms = 99,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);

    const publish_msg = try buildPublish(std.testing.allocator, 2, record);
    defer std.testing.allocator.free(publish_msg);
    const publish_decoded = try protocol.decode(publish_msg);
    try std.testing.expectEqual(protocol.MessageKind.publish, publish_decoded.kind);
    try std.testing.expect(std.mem.indexOf(u8, publish_decoded.payload, "sig=") != null);

    const refresh_msg = try buildRefresh(std.testing.allocator, 3, record);
    defer std.testing.allocator.free(refresh_msg);
    const refresh_decoded = try protocol.decode(refresh_msg);
    try std.testing.expectEqual(protocol.MessageKind.refresh, refresh_decoded.kind);
}

test "discovery client parses lookup response peer records" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd5} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.51", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-client-2", .relay_address = "relay.example.net:5443" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    const wire = try record.wirePayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(wire);

    const response = try protocol.encode(std.testing.allocator, .{
        .kind = .response,
        .correlation_id = 4,
        .node_hex = &record.node_id.toHex(),
        .payload = wire,
    });
    defer std.testing.allocator.free(response);

    var parsed = try parseLookupResponse(std.testing.allocator, response);
    defer parsed.deinit();
    try std.testing.expect(parsed.record.signature != null);
    try std.testing.expect(try parsed.record.verify(std.testing.allocator, kp.public_key));
}

test "discovery client rejects lookup response when node hex does not match payload record" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xd9} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.52", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-client-mismatch", .relay_address = "relay.example.net:6443" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    const wire = try record.wirePayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(wire);

    const response = try protocol.encode(std.testing.allocator, .{
        .kind = .response,
        .correlation_id = 5,
        .node_hex = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        .payload = wire,
    });
    defer std.testing.allocator.free(response);

    try std.testing.expectError(MeshError.InvalidPeerRecord, parseLookupResponse(std.testing.allocator, response));
}

test "discovery client parses lookup response only for expected correlation id" {
    const kp = try libself.identity.KeyPair.fromSeed([_]u8{0xda} ** 32);
    const did = try libself.DidKey.fromKeyPair(kp).encode(std.testing.allocator);
    defer std.testing.allocator.free(did);
    const endpoints = [_]@import("../peer/endpoint.zig").PublishedEndpoint{
        .{ .host = "203.0.113.53", .port = 4433 },
    };
    const hints = [_]@import("../peer/relay_hint.zig").RelayHint{
        .{ .relay_id = "relay-client-corr", .relay_address = "relay.example.net:7443" },
    };
    var record = PeerRecord{
        .node_id = libself.NodeId.fromPublicKey(kp.public_key),
        .did = did,
        .published_at_ms = 10,
        .expires_at_ms = 100,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, kp);
    const wire = try record.wirePayloadAlloc(std.testing.allocator);
    defer std.testing.allocator.free(wire);

    const response = try protocol.encode(std.testing.allocator, .{
        .kind = .response,
        .correlation_id = 66,
        .node_hex = &record.node_id.toHex(),
        .payload = wire,
    });
    defer std.testing.allocator.free(response);

    var parsed = try parseLookupResponseForCorrelation(std.testing.allocator, 66, response);
    defer parsed.deinit();
    try std.testing.expectError(
        MeshError.InvalidPeerRecord,
        parseLookupResponseForCorrelation(std.testing.allocator, 67, response),
    );
}
