const MeshError = @import("../common/error.zig").MeshError;
const Exchange = @import("exchange.zig").Exchange;
const protocol = @import("protocol.zig");

pub const Client = struct {
    exchange: *Exchange,
    local_node: []const u8,

    pub fn sendConnectRequest(self: Client, remote_node: []const u8, correlation_id: u64) MeshError!void {
        try self.exchange.send(self.local_node, remote_node, .{
            .kind = .connect_request,
            .from_node = self.local_node,
            .to_node = remote_node,
            .correlation_id = correlation_id,
            .payload = "",
        });
    }

    pub fn sendConnectAccept(self: Client, remote_node: []const u8, correlation_id: u64) MeshError!void {
        try self.exchange.send(self.local_node, remote_node, .{
            .kind = .connect_accept,
            .from_node = self.local_node,
            .to_node = remote_node,
            .correlation_id = correlation_id,
            .payload = "",
        });
    }

    pub fn sendConnectReject(self: Client, remote_node: []const u8, correlation_id: u64, reason: []const u8) MeshError!void {
        try self.exchange.send(self.local_node, remote_node, .{
            .kind = .connect_reject,
            .from_node = self.local_node,
            .to_node = remote_node,
            .correlation_id = correlation_id,
            .payload = reason,
        });
    }

    pub fn sendCandidate(self: Client, remote_node: []const u8, correlation_id: u64, payload: []const u8) MeshError!void {
        try self.exchange.send(self.local_node, remote_node, .{
            .kind = .candidate,
            .from_node = self.local_node,
            .to_node = remote_node,
            .correlation_id = correlation_id,
            .payload = payload,
        });
    }

    pub fn sendSetupPayload(self: Client, remote_node: []const u8, correlation_id: u64, payload: []const u8) MeshError!void {
        try self.exchange.send(self.local_node, remote_node, .{
            .kind = .setup_payload,
            .from_node = self.local_node,
            .to_node = remote_node,
            .correlation_id = correlation_id,
            .payload = payload,
        });
    }
};

test "signaling client sends connect request envelope" {
    const std = @import("std");
    var exchange = Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    const client = Client{
        .exchange = &exchange,
        .local_node = "node-a",
    };

    try client.sendConnectRequest("node-b", 5);
    const env = exchange.recv("node-b").?;
    defer {
        std.testing.allocator.free(env.from_node);
        std.testing.allocator.free(env.to_node);
    }
    try std.testing.expectEqual(protocol.MessageKind.connect_request, env.message.kind);
    try std.testing.expectEqual(@as(u64, 5), env.message.correlation_id);
}
