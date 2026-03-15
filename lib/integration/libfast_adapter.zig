const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;
const target_mod = @import("libfast.zig");

pub const ConnectionId = u64;

pub const VTable = struct {
    connect: *const fn (ctx: *anyopaque, target: target_mod.ConnectionTarget) MeshError!ConnectionId,
    send: *const fn (ctx: *anyopaque, connection_id: ConnectionId, payload: []const u8) MeshError!void,
    recv: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, connection_id: ConnectionId) MeshError!?[]u8,
    close: *const fn (ctx: *anyopaque, connection_id: ConnectionId) MeshError!void,
};

pub const Driver = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub fn connect(self: Driver, target: target_mod.ConnectionTarget) MeshError!ConnectionId {
        return self.vtable.connect(self.ctx, target);
    }

    pub fn send(self: Driver, connection_id: ConnectionId, payload: []const u8) MeshError!void {
        try self.vtable.send(self.ctx, connection_id, payload);
    }

    pub fn recv(self: Driver, allocator: std.mem.Allocator, connection_id: ConnectionId) MeshError!?[]u8 {
        return self.vtable.recv(self.ctx, allocator, connection_id);
    }

    pub fn close(self: Driver, connection_id: ConnectionId) MeshError!void {
        try self.vtable.close(self.ctx, connection_id);
    }
};

pub const Session = struct {
    driver: Driver,
    connection_id: ConnectionId,

    pub fn open(driver: Driver, target: target_mod.ConnectionTarget) MeshError!Session {
        const connection_id = try driver.connect(target);
        return .{
            .driver = driver,
            .connection_id = connection_id,
        };
    }

    pub fn send(self: Session, payload: []const u8) MeshError!void {
        try self.driver.send(self.connection_id, payload);
    }

    pub fn recv(self: Session, allocator: std.mem.Allocator) MeshError!?[]u8 {
        return self.driver.recv(allocator, self.connection_id);
    }

    pub fn close(self: Session) MeshError!void {
        try self.driver.close(self.connection_id);
    }
};

test "libfast adapter opens session and relays send/recv/close through driver" {
    const Fake = struct {
        next_id: u64 = 1,
        last_connected_direct_host: ?[]const u8 = null,
        last_sent_id: u64 = 0,
        last_sent_payload: []const u8 = "",
        recv_payload: []const u8 = "pong",
        closed_id: u64 = 0,
    };
    const Impl = struct {
        fn connect(ctx_ptr: *anyopaque, target: target_mod.ConnectionTarget) MeshError!ConnectionId {
            const ctx: *Fake = @ptrCast(@alignCast(ctx_ptr));
            const id = ctx.next_id;
            ctx.next_id += 1;
            switch (target) {
                .direct => |direct| ctx.last_connected_direct_host = direct.host,
                .relay => {},
            }
            return id;
        }

        fn send(ctx_ptr: *anyopaque, connection_id: ConnectionId, payload: []const u8) MeshError!void {
            const ctx: *Fake = @ptrCast(@alignCast(ctx_ptr));
            ctx.last_sent_id = connection_id;
            ctx.last_sent_payload = payload;
        }

        fn recv(ctx_ptr: *anyopaque, allocator: std.mem.Allocator, _: ConnectionId) MeshError!?[]u8 {
            const ctx: *Fake = @ptrCast(@alignCast(ctx_ptr));
            return allocator.dupe(u8, ctx.recv_payload) catch MeshError.BufferTooSmall;
        }

        fn close(ctx_ptr: *anyopaque, connection_id: ConnectionId) MeshError!void {
            const ctx: *Fake = @ptrCast(@alignCast(ctx_ptr));
            ctx.closed_id = connection_id;
        }
    };

    var fake = Fake{};
    const driver = Driver{
        .ctx = &fake,
        .vtable = &.{
            .connect = Impl.connect,
            .send = Impl.send,
            .recv = Impl.recv,
            .close = Impl.close,
        },
    };

    const session = try Session.open(driver, .{
        .direct = .{
            .host = "198.51.100.250",
            .port = 4433,
            .alpn = "mesh/1",
        },
    });
    try std.testing.expectEqual(@as(u64, 1), session.connection_id);
    try std.testing.expectEqualStrings("198.51.100.250", fake.last_connected_direct_host.?);

    try session.send("ping");
    try std.testing.expectEqual(@as(u64, 1), fake.last_sent_id);
    try std.testing.expectEqualStrings("ping", fake.last_sent_payload);

    const recv = (try session.recv(std.testing.allocator)).?;
    defer std.testing.allocator.free(recv);
    try std.testing.expectEqualStrings("pong", recv);

    try session.close();
    try std.testing.expectEqual(@as(u64, 1), fake.closed_id);
}
