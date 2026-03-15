const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

const Request = struct {
    from_node: []const u8,
    to_node: []const u8,
    correlation_id: u64,
    accepted: bool = false,
};

pub const Rendezvous = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayList(Request),

    pub fn init(allocator: std.mem.Allocator) Rendezvous {
        return .{
            .allocator = allocator,
            .requests = .empty,
        };
    }

    pub fn deinit(self: *Rendezvous) void {
        self.requests.deinit(self.allocator);
    }

    pub fn request(self: *Rendezvous, from_node: []const u8, to_node: []const u8, correlation_id: u64) MeshError!void {
        if (correlation_id == 0) return MeshError.InvalidPeerRecord;
        if (self.find(correlation_id) != null) return MeshError.Duplicate;
        self.requests.append(self.allocator, .{
            .from_node = from_node,
            .to_node = to_node,
            .correlation_id = correlation_id,
        }) catch return MeshError.BufferTooSmall;
    }

    pub fn accept(self: *Rendezvous, correlation_id: u64) MeshError!void {
        const idx = self.find(correlation_id) orelse return MeshError.NotFound;
        self.requests.items[idx].accepted = true;
    }

    pub fn reject(self: *Rendezvous, correlation_id: u64) MeshError!void {
        const idx = self.find(correlation_id) orelse return MeshError.NotFound;
        _ = self.requests.swapRemove(idx);
    }

    pub fn isAccepted(self: *const Rendezvous, correlation_id: u64) bool {
        const idx = self.find(correlation_id) orelse return false;
        return self.requests.items[idx].accepted;
    }

    fn find(self: *const Rendezvous, correlation_id: u64) ?usize {
        for (self.requests.items, 0..) |request_entry, idx| {
            if (request_entry.correlation_id == correlation_id) return idx;
        }
        return null;
    }
};

test "Rendezvous request and accept marks request accepted" {
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    try rendezvous.request("node-a", "node-b", 1);
    try rendezvous.accept(1);
    try std.testing.expect(rendezvous.isAccepted(1));
}

test "Rendezvous reject removes request" {
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    try rendezvous.request("node-a", "node-b", 2);
    try rendezvous.reject(2);
    try std.testing.expect(!rendezvous.isAccepted(2));
}

test "Rendezvous rejects duplicate correlation ids" {
    var rendezvous = Rendezvous.init(std.testing.allocator);
    defer rendezvous.deinit();

    try rendezvous.request("node-a", "node-b", 3);
    try std.testing.expectError(MeshError.Duplicate, rendezvous.request("node-a", "node-b", 3));
}
