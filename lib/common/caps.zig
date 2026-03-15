const std = @import("std");

pub const Capabilities = struct {
    discovery: bool = false,
    signaling: bool = false,
    relay_stream: bool = false,
    relay_datagram: bool = false,

    pub fn supportsRelay(self: Capabilities) bool {
        return self.relay_stream or self.relay_datagram;
    }
};

test "capability helper identifies relay support" {
    const none = Capabilities{};
    try std.testing.expect(!none.supportsRelay());

    const stream_only = Capabilities{ .relay_stream = true };
    try std.testing.expect(stream_only.supportsRelay());
}
