const std = @import("std");
const libself = @import("libself");

pub const TrustBridge = struct {
    store: *libself.TrustStore,

    pub fn evaluate(
        self: TrustBridge,
        mode: libself.TrustMode,
        subject: []const u8,
        did: []const u8,
    ) !libself.TrustDecision {
        return self.store.evaluate(mode, subject, did);
    }
};

test "TrustBridge forwards accept_any decisions" {
    var store = libself.TrustStore.init(std.testing.allocator);
    defer store.deinit();

    const bridge = TrustBridge{ .store = &store };
    try std.testing.expectEqual(
        libself.TrustDecision.accepted,
        try bridge.evaluate(.accept_any, "peer-a", "did:key:za"),
    );
}

test "TrustBridge supports TOFU pinning behavior" {
    var store = libself.TrustStore.init(std.testing.allocator);
    defer store.deinit();

    const bridge = TrustBridge{ .store = &store };
    try std.testing.expectEqual(
        libself.TrustDecision.accepted_and_pinned,
        try bridge.evaluate(.tofu, "peer-b", "did:key:zb"),
    );
    try std.testing.expectEqual(
        libself.TrustDecision.rejected,
        try bridge.evaluate(.tofu, "peer-b", "did:key:z-other"),
    );
}
