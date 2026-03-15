const std = @import("std");
const libmesh = @import("libmesh");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var store = libmesh.discovery.store.InMemoryStore.init(allocator);
    defer store.deinit();

    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x51} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.10", .port = 4433 },
    };
    const hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-example", .relay_address = "relay.example.net:4433" },
    };
    var record = libmesh.peer.peer_record.PeerRecord{
        .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(allocator, key_pair);

    try libmesh.api.publishSelf(&store, key_pair.public_key, record, 20);
    _ = try libmesh.api.lookupPeer(&store, key_pair.public_key, record.node_id);
    std.debug.print("publish_lookup example completed\n", .{});
}

test "publish_lookup example flow publishes and resolves local record" {
    var store = libmesh.discovery.store.InMemoryStore.init(std.testing.allocator);
    defer store.deinit();

    const key_pair = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x52} ** 32);
    const endpoints = [_]libmesh.peer.endpoint.PublishedEndpoint{
        .{ .host = "198.51.100.11", .port = 4433 },
    };
    const hints = [_]libmesh.peer.relay_hint.RelayHint{
        .{ .relay_id = "relay-example-2", .relay_address = "relay.example.net:5443" },
    };
    var record = libmesh.peer.peer_record.PeerRecord{
        .node_id = libmesh.Foundation.NodeId.fromPublicKey(key_pair.public_key),
        .published_at_ms = 10,
        .expires_at_ms = 1000,
        .endpoints = &endpoints,
        .relay_hints = &hints,
    };
    try record.sign(std.testing.allocator, key_pair);
    try libmesh.api.publishSelf(&store, key_pair.public_key, record, 20);

    const loaded = try libmesh.api.lookupPeer(&store, key_pair.public_key, record.node_id);
    try std.testing.expect(try loaded.verify(std.testing.allocator, key_pair.public_key));
}
