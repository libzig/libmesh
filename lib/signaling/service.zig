const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const Exchange = @import("exchange.zig").Exchange;
const Rendezvous = @import("rendezvous.zig").Rendezvous;
const Client = @import("client.zig").Client;
const Server = @import("server.zig").Server;
const protocol = @import("protocol.zig");

pub const Service = struct {
    exchange: *Exchange,
    rendezvous: *Rendezvous,

    pub fn requestConnect(self: Service, from_node: []const u8, to_node: []const u8, correlation_id: u64) MeshError!void {
        const client = Client{
            .exchange = self.exchange,
            .local_node = from_node,
        };
        try client.sendConnectRequest(to_node, correlation_id);
    }

    pub fn acceptConnect(self: Service, from_node: []const u8, to_node: []const u8, correlation_id: u64) MeshError!void {
        const client = Client{
            .exchange = self.exchange,
            .local_node = from_node,
        };
        try client.sendConnectAccept(to_node, correlation_id);
    }

    pub fn rejectConnect(self: Service, from_node: []const u8, to_node: []const u8, correlation_id: u64, reason: []const u8) MeshError!void {
        const client = Client{
            .exchange = self.exchange,
            .local_node = from_node,
        };
        try client.sendConnectReject(to_node, correlation_id, reason);
    }

    pub fn sendSetupPayload(self: Service, from_node: []const u8, to_node: []const u8, correlation_id: u64, payload: []const u8) MeshError!void {
        const client = Client{
            .exchange = self.exchange,
            .local_node = from_node,
        };
        try client.sendSetupPayload(to_node, correlation_id, payload);
    }

    pub fn processNext(self: Service, local_node: []const u8) MeshError!?protocol.Message {
        const server = Server{
            .exchange = self.exchange,
            .rendezvous = self.rendezvous,
            .local_node = local_node,
        };
        return server.processNext();
    }
};

test "signaling service coordinates connect request and accept flow" {
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const service = Service{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };

    try service.requestConnect("node-a", "node-b", 11);
    const req = (try service.processNext("node-b")).?;
    try std.testing.expectEqual(protocol.MessageKind.connect_request, req.kind);
    try std.testing.expect(!rendezvous.isAccepted(11));

    try service.acceptConnect("node-b", "node-a", 11);
    const ack = (try service.processNext("node-a")).?;
    try std.testing.expectEqual(protocol.MessageKind.connect_accept, ack.kind);
    try std.testing.expect(rendezvous.isAccepted(11));
}

test "signaling service forwards setup payload between peers" {
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const service = Service{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };

    try service.sendSetupPayload("node-a", "node-b", 22, "candidate-bundle");
    const message = (try service.processNext("node-b")).?;
    try std.testing.expectEqual(protocol.MessageKind.setup_payload, message.kind);
    try std.testing.expectEqualStrings("candidate-bundle", message.payload);
}
