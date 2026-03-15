const std = @import("std");
const libself = @import("libself");
const MeshError = @import("../common/error.zig").MeshError;
const RelaySession = @import("session.zig").RelaySession;
const OpenResult = @import("server.zig").OpenResult;
const Server = @import("server.zig").Server;
const bridge_streams = @import("bridge_streams.zig");
const bridge_datagrams = @import("bridge_datagrams.zig");

pub const Service = struct {
    server: *Server,

    pub fn open(
        self: Service,
        id: u64,
        source_public_key: libself.identity.PublicKey,
        source_did: []const u8,
        target_public_key: libself.identity.PublicKey,
        target_did: []const u8,
    ) MeshError!OpenResult {
        return self.server.open(id, source_public_key, source_did, target_public_key, target_did);
    }

    pub fn close(self: Service, session_id: u64) bool {
        return self.server.close(session_id);
    }

    pub fn forwardStream(
        _: Service,
        allocator: std.mem.Allocator,
        session: RelaySession,
        sink: *std.ArrayList(u8),
        chunk: []const u8,
    ) MeshError!usize {
        return bridge_streams.forward(allocator, session, sink, chunk);
    }

    pub fn forwardDatagram(_: Service, allocator: std.mem.Allocator, session: RelaySession, datagram: []const u8) MeshError![]u8 {
        return bridge_datagrams.forward(allocator, session, datagram);
    }
};

test "relay service opens sessions and reports match when reverse peer arrives" {
    var matcher = @import("matcher.zig").Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 8,
        .require_authenticated = true,
    });
    defer server.deinit();
    const service = Service{ .server = &server };

    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xd5} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xd6} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    const first = try service.open(1, source.public_key, source_did, target.public_key, target_did);
    try std.testing.expect(first.matched == null);

    const second = try service.open(2, target.public_key, target_did, source.public_key, source_did);
    try std.testing.expect(second.matched != null);
}

test "relay service forwards streams and datagrams for authenticated sessions" {
    const source = try libself.identity.KeyPair.fromSeed([_]u8{0xd7} ** 32);
    const target = try libself.identity.KeyPair.fromSeed([_]u8{0xd8} ** 32);
    const allocator = std.testing.allocator;
    const source_did = try libself.DidKey.fromKeyPair(source).encode(allocator);
    defer allocator.free(source_did);
    const target_did = try libself.DidKey.fromKeyPair(target).encode(allocator);
    defer allocator.free(target_did);

    const session = try @import("session.zig").openAuthenticated(
        7,
        source.public_key,
        source_did,
        target.public_key,
        target_did,
    );

    var matcher = @import("matcher.zig").Matcher.init(std.testing.allocator);
    defer matcher.deinit();
    var server = Server.init(std.testing.allocator, &matcher, .{
        .max_sessions = 2,
        .require_authenticated = true,
    });
    defer server.deinit();
    const service = Service{ .server = &server };

    var sink = std.ArrayList(u8).empty;
    defer sink.deinit(allocator);
    const written = try service.forwardStream(allocator, session, &sink, "hello-stream");
    try std.testing.expectEqual(@as(usize, 12), written);
    try std.testing.expectEqualStrings("hello-stream", sink.items);

    const datagram = try service.forwardDatagram(allocator, session, "hi");
    defer allocator.free(datagram);
    try std.testing.expectEqualStrings("hi", datagram);
}
