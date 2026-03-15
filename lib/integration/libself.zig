const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;

pub const Signature = libself.identity.Signature;

pub fn nodeIdFromPublicKey(public_key: libself.identity.PublicKey) libself.NodeId {
    return libself.NodeId.fromPublicKey(public_key);
}

pub fn didFromKeyPair(allocator: std.mem.Allocator, key_pair: libself.identity.KeyPair) MeshError![]u8 {
    return libself.DidKey.fromKeyPair(key_pair).encode(allocator) catch MeshError.BufferTooSmall;
}

pub fn parseDid(did: []const u8) MeshError!libself.DidKey {
    return libself.DidKey.parse(std.heap.page_allocator, did) catch MeshError.AccessDenied;
}

pub fn verifyDidMatchesPublicKey(did: []const u8, public_key: libself.identity.PublicKey) MeshError!void {
    const parsed = try parseDid(did);
    if (!std.mem.eql(u8, &parsed.public_key, &public_key)) return MeshError.AccessDenied;
}

pub fn signPayload(payload: []const u8, key_pair: libself.identity.KeyPair) MeshError!Signature {
    return key_pair.sign(payload) catch MeshError.AccessDenied;
}

pub fn verifyPayload(payload: []const u8, signature: Signature, public_key: libself.identity.PublicKey) bool {
    return libself.identity.verifyWithPublicKey(payload, signature, public_key);
}

test "libself integration binds node ids and did:key values to key material" {
    const key_pair = try libself.identity.KeyPair.fromSeed([_]u8{0x81} ** 32);
    const node_id = nodeIdFromPublicKey(key_pair.public_key);
    try std.testing.expect(node_id.toHex().len == 64);

    const did = try didFromKeyPair(std.testing.allocator, key_pair);
    defer std.testing.allocator.free(did);
    try std.testing.expect(std.mem.startsWith(u8, did, "did:key:"));
    try verifyDidMatchesPublicKey(did, key_pair.public_key);
}

test "libself integration verifies signatures and rejects key mismatch" {
    const signer = try libself.identity.KeyPair.fromSeed([_]u8{0x82} ** 32);
    const other = try libself.identity.KeyPair.fromSeed([_]u8{0x83} ** 32);
    const payload = "mesh-payload";
    const sig = try signPayload(payload, signer);
    try std.testing.expect(verifyPayload(payload, sig, signer.public_key));
    try std.testing.expect(!verifyPayload(payload, sig, other.public_key));
}
