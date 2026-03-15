const RelaySession = @import("session.zig").RelaySession;

pub const Policy = struct {
    max_sessions: usize = 1024,
    require_authenticated: bool = true,

    pub fn allow(self: Policy, active_sessions: usize, session: RelaySession) bool {
        if (active_sessions >= self.max_sessions) return false;
        if (self.require_authenticated and !session.authenticated) return false;
        return true;
    }
};

test "relay policy enforces auth and max session limits" {
    const libself = @import("libself");
    const kp1 = try libself.identity.KeyPair.fromSeed([_]u8{0xf1} ** 32);
    const kp2 = try libself.identity.KeyPair.fromSeed([_]u8{0xf2} ** 32);
    const session = RelaySession{
        .id = 1,
        .source_node_id = libself.NodeId.fromPublicKey(kp1.public_key),
        .target_node_id = libself.NodeId.fromPublicKey(kp2.public_key),
        .source_did = "did:key:s",
        .target_did = "did:key:t",
        .authenticated = true,
    };

    const strict = Policy{ .max_sessions = 1, .require_authenticated = true };
    try @import("std").testing.expect(strict.allow(0, session));
    try @import("std").testing.expect(!strict.allow(1, session));

    const unauth = RelaySession{
        .id = 2,
        .source_node_id = session.source_node_id,
        .target_node_id = session.target_node_id,
        .source_did = session.source_did,
        .target_did = session.target_did,
        .authenticated = false,
    };
    try @import("std").testing.expect(!strict.allow(0, unauth));
}
