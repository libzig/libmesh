const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;

pub const RelaySession = struct {
    id: u64,
    source_node_id: libself.NodeId,
    target_node_id: libself.NodeId,
    source_did: []const u8,
    target_did: []const u8,
    authenticated: bool,
};

pub fn openAuthenticated(
    id: u64,
    source_public_key: libself.identity.PublicKey,
    source_did: []const u8,
    target_public_key: libself.identity.PublicKey,
    target_did: []const u8,
) MeshError!RelaySession {
    if (id == 0) return MeshError.InvalidPeerRecord;

    const parsed_source = libself.DidKey.parse(std.heap.page_allocator, source_did) catch return MeshError.AccessDenied;
    const parsed_target = libself.DidKey.parse(std.heap.page_allocator, target_did) catch return MeshError.AccessDenied;

    if (!std.mem.eql(u8, &parsed_source.public_key, &source_public_key)) return MeshError.AccessDenied;
    if (!std.mem.eql(u8, &parsed_target.public_key, &target_public_key)) return MeshError.AccessDenied;

    const source_node_id = libself.NodeId.fromPublicKey(source_public_key);
    const target_node_id = libself.NodeId.fromPublicKey(target_public_key);
    if (std.mem.eql(u8, &source_node_id.toBytes(), &target_node_id.toBytes())) return MeshError.InvalidPeerRecord;

    return .{
        .id = id,
        .source_node_id = source_node_id,
        .target_node_id = target_node_id,
        .source_did = source_did,
        .target_did = target_did,
        .authenticated = true,
    };
}

test "openAuthenticated accepts matching did:key/public-key pairs" {
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0x91} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0x92} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    const session = try openAuthenticated(1, source.public_key, source_did, target.public_key, target_did);
    try std.testing.expect(session.authenticated);
}

test "openAuthenticated rejects did/key mismatches" {
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0x93} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0x94} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    try std.testing.expectError(
        MeshError.AccessDenied,
        openAuthenticated(1, source.public_key, target_did, target.public_key, source_did),
    );
}
