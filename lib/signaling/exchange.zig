const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const Message = @import("protocol.zig").Message;

const Envelope = struct {
    from_node: []u8,
    to_node: []u8,
    message: Message,
};

pub const Exchange = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Envelope),

    pub fn init(allocator: std.mem.Allocator) Exchange {
        return .{
            .allocator = allocator,
            .queue = .empty,
        };
    }

    pub fn deinit(self: *Exchange) void {
        for (self.queue.items) |env| {
            self.allocator.free(env.from_node);
            self.allocator.free(env.to_node);
        }
        self.queue.deinit(self.allocator);
    }

    pub fn send(self: *Exchange, from_node: []const u8, to_node: []const u8, message: Message) MeshError!void {
        if (from_node.len == 0 or to_node.len == 0) return MeshError.InvalidPeerRecord;
        const from_owned = self.allocator.dupe(u8, from_node) catch return MeshError.BufferTooSmall;
        errdefer self.allocator.free(from_owned);
        const to_owned = self.allocator.dupe(u8, to_node) catch return MeshError.BufferTooSmall;
        errdefer self.allocator.free(to_owned);

        self.queue.append(self.allocator, .{
            .from_node = from_owned,
            .to_node = to_owned,
            .message = message,
        }) catch return MeshError.BufferTooSmall;
    }

    pub fn recv(self: *Exchange, to_node: []const u8) ?Envelope {
        for (self.queue.items, 0..) |env, idx| {
            if (std.mem.eql(u8, env.to_node, to_node)) {
                return self.queue.orderedRemove(idx);
            }
        }
        return null;
    }
};

test "Exchange send and recv delivers signaling payload to target peer" {
    var ex = Exchange.init(std.testing.allocator);
    defer ex.deinit();

    try ex.send("node-a", "node-b", .{
        .kind = .setup_payload,
        .from_node = "node-a",
        .to_node = "node-b",
        .correlation_id = 1,
        .payload = "hello",
    });

    const got = ex.recv("node-b").?;
    defer {
        std.testing.allocator.free(got.from_node);
        std.testing.allocator.free(got.to_node);
    }
    try std.testing.expectEqualStrings("node-a", got.from_node);
    try std.testing.expectEqualStrings("hello", got.message.payload);
}

test "Exchange recv returns null when no message targets peer" {
    var ex = Exchange.init(std.testing.allocator);
    defer ex.deinit();
    try std.testing.expect(ex.recv("missing") == null);
}
