const std = @import("std");
const MeshError = @import("../common/error.zig").MeshError;

pub const RelayHint = struct {
    relay_id: []const u8,
    relay_address: []const u8,
    relay_alpn: []const u8 = "mesh-relay/1",
    priority: i16 = 0,
    expires_at_ms: ?u64 = null,

    pub fn validate(self: RelayHint) MeshError!void {
        if (self.relay_id.len == 0) return MeshError.InvalidRelayHint;
        if (self.relay_address.len == 0) return MeshError.InvalidRelayHint;
        if (std.mem.indexOfAny(u8, self.relay_id, " \t\r\n") != null) return MeshError.InvalidRelayHint;
        if (std.mem.indexOfAny(u8, self.relay_address, " \t\r\n") != null) return MeshError.InvalidRelayHint;
    }
};

test "RelayHint validates proper relay metadata" {
    const hint = RelayHint{
        .relay_id = "relay-node-1",
        .relay_address = "relay.example.net:4433",
        .priority = 1,
    };
    try hint.validate();
}

test "RelayHint rejects empty fields" {
    const bad = RelayHint{
        .relay_id = "",
        .relay_address = "",
    };
    try std.testing.expectError(MeshError.InvalidRelayHint, bad.validate());
}
