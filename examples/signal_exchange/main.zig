const std = @import("std");
const libmesh = @import("libmesh");

pub fn main() !void {
    var exchange = libmesh.signaling.exchange.Exchange.init(std.heap.page_allocator);
    defer exchange.deinit();
    var rendezvous = libmesh.signaling.rendezvous.Rendezvous.init(std.heap.page_allocator);
    defer rendezvous.deinit();

    const service = libmesh.signaling.service.Service{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };

    try service.requestConnect("node-a", "node-b", 7);
    _ = try service.processNext("node-b");
    try service.acceptConnect("node-b", "node-a", 7);
    _ = try service.processNext("node-a");
    try service.sendSetupPayload("node-a", "node-b", 7, "ice:bundle");
    _ = try service.processNext("node-b");
    std.debug.print("signal_exchange example completed\n", .{});
}

test "signal_exchange example flow drives connect and payload exchange" {
    var exchange = libmesh.signaling.exchange.Exchange.init(std.testing.allocator);
    defer exchange.deinit();
    var rendezvous = libmesh.signaling.rendezvous.Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    const service = libmesh.signaling.service.Service{
        .exchange = &exchange,
        .rendezvous = &rendezvous,
    };

    try service.requestConnect("node-a", "node-b", 9);
    const req = (try service.processNext("node-b")).?;
    try std.testing.expectEqual(libmesh.signaling.protocol.MessageKind.connect_request, req.kind);

    try service.acceptConnect("node-b", "node-a", 9);
    const ack = (try service.processNext("node-a")).?;
    try std.testing.expectEqual(libmesh.signaling.protocol.MessageKind.connect_accept, ack.kind);
    try std.testing.expect(rendezvous.isAccepted(9));
}
