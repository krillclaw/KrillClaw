const std = @import("std");
const fs = @import("filesystem.zig");

/// Persistent memory store for KrillClaw.
///
/// Provides typed access to the flash filesystem:
/// - Config files: /config/*.md (system prompt, personality, tool settings)
/// - Memory files: /memory/*.md (conversation summaries, learned facts)
/// - Sessions: /sessions/*.jsonl (raw conversation logs)
///
/// All operations are atomic and respect flash file size limits.

pub const Store = struct {
    filesystem: fs.FileSystem,

    pub fn init(backend: fs.Backend) Store {
        return .{
            .filesystem = fs.FileSystem.init(backend),
        };
    }

    /// Mount the store; creates directory structure.
    pub fn mount(self: *Store) fs.Error!void {
        try self.filesystem.mount();
    }

    // ---- Config operations (/config/*.md) ----

    pub fn readConfig(self: *Store, name: []const u8, buf: *fs.FileBuffer) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "config/", name);
        try self.filesystem.read(path, buf);
    }

    pub fn writeConfig(self: *Store, name: []const u8, data: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "config/", name);
        try self.filesystem.atomicWrite(path, data);
    }

    pub fn deleteConfig(self: *Store, name: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "config/", name);
        try self.filesystem.delete(path);
    }

    pub fn listConfigs(self: *Store, out: *fs.DirListing) fs.Error!void {
        try self.filesystem.list("config", out);
    }

    // ---- Memory operations (/memory/*.md) ----

    pub fn readMemory(self: *Store, name: []const u8, buf: *fs.FileBuffer) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "memory/", name);
        try self.filesystem.read(path, buf);
    }

    pub fn writeMemory(self: *Store, name: []const u8, data: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "memory/", name);
        try self.filesystem.atomicWrite(path, data);
    }

    pub fn deleteMemory(self: *Store, name: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "memory/", name);
        try self.filesystem.delete(path);
    }

    pub fn listMemories(self: *Store, out: *fs.DirListing) fs.Error!void {
        try self.filesystem.list("memory", out);
    }

    // ---- Session operations (/sessions/*.jsonl) ----

    /// Append a JSONL line to a session file.
    /// Since we can't do partial writes atomically on flash,
    /// this reads the existing content, appends, and writes back.
    pub fn appendSession(self: *Store, name: []const u8, line: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "sessions/", name);

        var buf = fs.FileBuffer{};
        self.filesystem.read(path, &buf) catch |err| {
            if (err == fs.Error.FileNotFound) {
                // New file — just write the line + newline
                if (line.len + 1 > fs.MAX_FILE_SIZE) return fs.Error.FileTooLarge;
                var newbuf: [fs.MAX_FILE_SIZE]u8 = undefined;
                @memcpy(newbuf[0..line.len], line);
                newbuf[line.len] = '\n';
                try self.filesystem.atomicWrite(path, newbuf[0 .. line.len + 1]);
                return;
            }
            return err;
        };

        // Append line + newline
        const new_len = buf.len + line.len + 1;
        if (new_len > fs.MAX_FILE_SIZE) return fs.Error.FileTooLarge;
        @memcpy(buf.data[buf.len .. buf.len + line.len], line);
        buf.data[buf.len + line.len] = '\n';
        buf.len = new_len;
        try self.filesystem.atomicWrite(path, buf.slice());
    }

    pub fn readSession(self: *Store, name: []const u8, buf: *fs.FileBuffer) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "sessions/", name);
        try self.filesystem.read(path, buf);
    }

    pub fn deleteSession(self: *Store, name: []const u8) fs.Error!void {
        var pathbuf: [fs.MAX_PATH_LEN]u8 = undefined;
        const path = buildPath(&pathbuf, "sessions/", name);
        try self.filesystem.delete(path);
    }

    pub fn listSessions(self: *Store, out: *fs.DirListing) fs.Error!void {
        try self.filesystem.list("sessions", out);
    }

    // ---- Helpers ----

    fn buildPath(out: *[fs.MAX_PATH_LEN]u8, prefix: []const u8, name: []const u8) []const u8 {
        @memcpy(out[0..prefix.len], prefix);
        const name_len = @min(name.len, fs.MAX_PATH_LEN - prefix.len);
        @memcpy(out[prefix.len .. prefix.len + name_len], name[0..name_len]);
        return out[0 .. prefix.len + name_len];
    }
};

// ---- Tests ----

test "Store config round-trip" {
    var pb = try fs.PosixBackend.init("/tmp/krillclaw_test_store");
    const back = pb.backend();
    var store = Store.init(back);
    try store.mount();

    try store.writeConfig("agent.md", "# Agent Config\nmodel: small");
    var buf = fs.FileBuffer{};
    try store.readConfig("agent.md", &buf);
    try std.testing.expectEqualStrings("# Agent Config\nmodel: small", buf.slice());

    try store.deleteConfig("agent.md");
}

test "Store memory round-trip" {
    var pb = try fs.PosixBackend.init("/tmp/krillclaw_test_store");
    const back = pb.backend();
    var store = Store.init(back);
    try store.mount();

    try store.writeMemory("facts.md", "# Facts\n- Zig is great");
    var buf = fs.FileBuffer{};
    try store.readMemory("facts.md", &buf);
    try std.testing.expectEqualStrings("# Facts\n- Zig is great", buf.slice());

    try store.deleteMemory("facts.md");
}

test "Store session append" {
    var pb = try fs.PosixBackend.init("/tmp/krillclaw_test_store");
    const back = pb.backend();
    var store = Store.init(back);
    try store.mount();

    // Clean up first
    store.deleteSession("test.jsonl") catch {};

    try store.appendSession("test.jsonl", "{\"role\":\"user\",\"msg\":\"hi\"}");
    try store.appendSession("test.jsonl", "{\"role\":\"assistant\",\"msg\":\"hello\"}");

    var buf = fs.FileBuffer{};
    try store.readSession("test.jsonl", &buf);

    // Should have two lines
    const content = buf.slice();
    var lines: usize = 0;
    for (content) |c| {
        if (c == '\n') lines += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), lines);

    try store.deleteSession("test.jsonl");
}

test "Store list operations" {
    var pb = try fs.PosixBackend.init("/tmp/krillclaw_test_store");
    const back = pb.backend();
    var store = Store.init(back);
    try store.mount();

    try store.writeConfig("a.md", "a");
    try store.writeConfig("b.md", "b");

    var listing = fs.DirListing{};
    try store.listConfigs(&listing);
    try std.testing.expect(listing.count >= 2);

    try store.deleteConfig("a.md");
    try store.deleteConfig("b.md");
}
