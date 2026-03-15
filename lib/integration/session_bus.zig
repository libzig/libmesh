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
                return self.queue.orderedRemove(idx);
            }
        }
        return null;
    }

    pub fn recvFrom(self: *SessionBus, to: []const u8, from: []const u8) ?Packet {
        for (self.queue.items, 0..) |packet, idx| {
            if (std.mem.eql(u8, packet.to, to) and std.mem.eql(u8, packet.from, from)) {
                return self.queue.orderedRemove(idx);
            }
        }
        return null;
    }

    pub fn pendingCount(self: *const SessionBus) usize {
        return self.queue.items.len;
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
    try std.testing.expectEqual(@as(usize, 2), bus.pendingCount());
    const packet = bus.recv("node-c").?;
    defer {
        std.testing.allocator.free(packet.from);
        std.testing.allocator.free(packet.to);
        std.testing.allocator.free(packet.payload);
    }
    try std.testing.expectEqualStrings("second", packet.payload);
    try std.testing.expectEqual(@as(usize, 1), bus.pendingCount());
}

test "SessionBus recvFrom selects packet by source and destination" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.send("node-a", "node-c", "from-a");
    try bus.send("node-b", "node-c", "from-b");
    const packet = bus.recvFrom("node-c", "node-b").?;
    defer {
        std.testing.allocator.free(packet.from);
        std.testing.allocator.free(packet.to);
        std.testing.allocator.free(packet.payload);
    }
    try std.testing.expectEqualStrings("from-b", packet.payload);
    try std.testing.expectEqual(@as(usize, 1), bus.pendingCount());
}

test "SessionBus recv preserves FIFO order for same destination" {
    var bus = SessionBus.init(std.testing.allocator);
    defer bus.deinit();

    try bus.send("node-a", "node-z", "first");
    try bus.send("node-b", "node-z", "second");

    const first = bus.recv("node-z").?;
    defer {
        std.testing.allocator.free(first.from);
        std.testing.allocator.free(first.to);
        std.testing.allocator.free(first.payload);
    }
    try std.testing.expectEqualStrings("first", first.payload);

    const second = bus.recv("node-z").?;
    defer {
        std.testing.allocator.free(second.from);
        std.testing.allocator.free(second.to);
        std.testing.allocator.free(second.payload);
    }
    try std.testing.expectEqualStrings("second", second.payload);
}
