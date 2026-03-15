const std = @import("std");
const libmesh = @import("libmesh");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var matcher = libmesh.relay.matcher.Matcher.init(allocator);
    defer matcher.deinit();
    var server = libmesh.relay.server.Server.init(allocator, &matcher, .{
        .max_sessions = 8,
        .require_authenticated = true,
    });
    defer server.deinit();

    const a = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x61} ** 32);
    const b = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x62} ** 32);
    const a_did = try libmesh.Foundation.DidKey.fromKeyPair(a).encode(allocator);
    defer allocator.free(a_did);
    const b_did = try libmesh.Foundation.DidKey.fromKeyPair(b).encode(allocator);
    defer allocator.free(b_did);

    const relay = libmesh.relay.service.Service{ .server = &server };
    _ = try relay.open(1, a.public_key, a_did, b.public_key, b_did);
    _ = try relay.open(2, b.public_key, b_did, a.public_key, a_did);
    std.debug.print("relay_pair example completed\n", .{});
}

test "relay_pair example opens reverse sessions and forwards stream bytes" {
    var matcher = libmesh.relay.matcher.Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = libmesh.relay.server.Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 8,
        .require_authenticated = true,
    });
    defer server.deinit();
    const relay = libmesh.relay.service.Service{ .server = &server };

    const a = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x63} ** 32);
    const b = try libmesh.Foundation.KeyPair.fromSeed([_]u8{0x64} ** 32);
    const a_did = try libmesh.Foundation.DidKey.fromKeyPair(a).encode(std.testing.allocator);
    defer std.testing.allocator.free(a_did);
    const b_did = try libmesh.Foundation.DidKey.fromKeyPair(b).encode(std.testing.allocator);
    defer std.testing.allocator.free(b_did);

    _ = try relay.open(11, a.public_key, a_did, b.public_key, b_did);
    const second = try relay.open(12, b.public_key, b_did, a.public_key, a_did);
    try std.testing.expect(second.matched != null);

    var sink = std.ArrayList(u8).empty;
    defer sink.deinit(std.testing.allocator);
    const written = try relay.forwardStream(std.testing.allocator, second.session, &sink, "relay-bytes");
    try std.testing.expectEqual(@as(usize, 11), written);
    try std.testing.expectEqualStrings("relay-bytes", sink.items);
}
