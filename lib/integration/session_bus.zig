const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const Packet = struct {
    from: []u8,
    to: []u8,
    payload: []u8,
};

pub const SessionBus = struct {
    allocator: std.mem.Allocator,
    queue: std.ArrayList(Packet),

    pub fn init(allocator: std.mem.Allocator) SessionBus {
        return .{
            .allocator = allocator,
            .queue = .empty,
        };
    }

    pub fn deinit(self: *SessionBus) void {
        for (self.queue.items) |packet| {
            self.allocator.free(packet.from);
            self.allocator.free(packet.to);
            self.allocator.free(packet.payload);
        }
        self.queue.deinit(self.allocator);
    }

    pub fn send(self: *SessionBus, from: []const u8, to: []const u8, payload: []const u8) MeshError!void {
        if (from.len == 0 or to.len == 0) return MeshError.InvalidPeerRecord;
        const from_owned = self.allocator.dupe(u8, from) catch return MeshError.BufferTooSmall;
        errdefer self.allocator.free(from_owned);
        const to_owned = self.allocator.dupe(u8, to) catch return MeshError.BufferTooSmall;
        errdefer self.allocator.free(to_owned);
        const payload_owned = self.allocator.dupe(u8, payload) catch return MeshError.BufferTooSmall;
        errdefer self.allocator.free(payload_owned);

        self.queue.append(self.allocator, .{
            .from = from_owned,
            .to = to_owned,
            .payload = payload_owned,
        }) catch return MeshError.BufferTooSmall;
    }

    pub fn recv(self: *SessionBus, to: []const u8) ?Packet {
        for (self.queue.items, 0..) |packet, idx| {
            if (std.mem.eql(u8, packet.to, to)) {
                return self.queue.swapRemove(idx);
            }
        }
        return null;
    }
};

test "SessionBus send and recv transfers packet payload to target" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.send("node-a", "node-b", "hello");
    const packet = bus.recv("node-b").?;
    defer {
        std.testing.allocator.free(packet.from);
        std.testing.allocator.free(packet.to);
        std.testing.allocator.free(packet.payload);
    }
    try std.testing.expectEqualStrings("node-a", packet.from);
    try std.testing.expectEqualStrings("hello", packet.payload);
}

test "SessionBus recv leaves unmatched packets in queue" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.send("node-a", "node-b", "first");
    try bus.send("node-a", "node-c", "second");
    const missing = bus.recv("node-x");
    try std.testing.expect(missing == null);
    const packet = bus.recv("node-c").?;
    defer {
        std.testing.allocator.free(packet.from);
        std.testing.allocator.free(packet.to);
        std.testing.allocator.free(packet.payload);
    }
    try std.testing.expectEqualStrings("second", packet.payload);
}
