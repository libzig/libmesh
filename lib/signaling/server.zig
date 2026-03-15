const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const Exchange = @import("exchange.zig").Exchange;
const Rendezvous = @import("rendezvous.zig").Rendezvous;
const protocol = @import("protocol.zig");

pub const Server = struct {
    exchange: *Exchange,
    rendezvous: *Rendezvous,
    local_node: []const u8,

    pub fn processNext(self: Server) MeshError!?protocol.Message {
        const env = self.exchange.recv(self.local_node) orelse return null;
        defer {
            self.exchange.allocator.free(env.from_node);
            self.exchange.allocator.free(env.to_node);
        }

        switch (env.message.kind) {
            .connect_request => self.rendezvous.request(env.from_node, env.to_node, env.message.correlation_id) catch |err| {
                if (err != MeshError.Duplicate) return err;
            },
            .connect_accept => try self.rendezvous.accept(env.message.correlation_id),
            .connect_reject => try self.rendezvous.reject(env.message.correlation_id),
            else => {},
        }
        return env.message;
    }
};

test "signaling server processes connect request and accept flow" {
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const client_a = @import("client.zig").Client{
        .exchange = &exchange,
        .local_node = "node-a",
    };
    const client_b = @import("client.zig").Client{
        .exchange = &exchange,
        .local_node = "node-b",
    };

    const server_b = Server{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
        .local_node = "node-b",
    };
    const server_a = Server{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
        .local_node = "node-a",
    };

    try client_a.sendConnectRequest("node-b", 11);
    const msg_request = (try server_b.processNext()).?;
    try std.testing.expectEqual(protocol.MessageKind.connect_request, msg_request.kind);
    try std.testing.expect(!rendezvous.isAccepted(11));

    try client_b.sendConnectAccept("node-a", 11);
    const msg_accept = (try server_a.processNext()).?;
    try std.testing.expectEqual(protocol.MessageKind.connect_accept, msg_accept.kind);
    try std.testing.expect(rendezvous.isAccepted(11));
}

test "signaling server treats duplicate connect request correlation as idempotent" {
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const client_a = @import("client.zig").Client{
        .exchange = &exchange,
        .local_node = "node-a",
    };
    const server_b = Server{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
        .local_node = "node-b",
    };

    try client_a.sendConnectRequest("node-b", 21);
    _ = try server_b.processNext();
    try client_a.sendConnectRequest("node-b", 21);
    _ = try server_b.processNext();
    try std.testing.expect(!rendezvous.isAccepted(21));
}
