const std = @import("std");

/// Valid provider names for validation.
pub const valid_providers = [_][]const u8{ "claude", "openai", "ollama" };

/// All recognized config keys.
pub const ConfigKey = enum {
    provider,
    model,
    api_key,
    wifi_ssid,
    wifi_pass,
    endpoint_url,

    pub fn toString(self: ConfigKey) []const u8 {
        return @tagName(self);
    }

    pub fn fromString(s: []const u8) ?ConfigKey {
        inline for (std.meta.fields(ConfigKey)) |f| {
            if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }
};

pub const key_count = std.meta.fields(ConfigKey).len;

/// Change notification callback.
pub const ChangeCallback = *const fn (key: ConfigKey, old: ?[]const u8, new: []const u8) void;

/// Compile-time defaults.
const defaults = [key_count]?[]const u8{
    "claude", // provider
    "claude-sonnet-4-20250514", // model
    null, // api_key
    null, // wifi_ssid
    null, // wifi_pass
    "https://api.anthropic.com", // endpoint_url
};

/// Runtime config manager with layered priority.
pub const ConfigManager = struct {
    values: [key_count]?[]const u8 = [_]?[]const u8{null} ** key_count,
    file_path: []const u8 = "krillclaw.conf",
    callback: ?ChangeCallback = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigManager {
        return .{ .allocator = allocator };
    }

    /// Get a config value with priority: stored value > compile-time default.
    pub fn get(self: *const ConfigManager, key: ConfigKey) ?[]const u8 {
        return self.values[@intFromEnum(key)] orelse defaults[@intFromEnum(key)];
    }

    /// Set a config value and fire change callback.
    pub fn set(self: *ConfigManager, key: ConfigKey, value: []const u8) !void {
        if (!validate(key, value)) return error.InvalidValue;
        const idx = @intFromEnum(key);
        const old = self.values[idx];
        self.values[idx] = try self.allocator.dupe(u8, value);
        if (self.callback) |cb| cb(key, old orelse defaults[idx], value);
        if (old) |o| self.allocator.free(o);
    }

    /// Load from key=value config file.
    pub fn loadFile(self: *ConfigManager) !void {
        const file = std.fs.cwd().openFile(self.file_path, .{}) catch |e| switch (e) {
            error.FileNotFound => return,
            else => return e,
        };
        defer file.close();
        var buf: [4096]u8 = undefined;
        const len = try file.readAll(&buf);
        var iter = std.mem.splitScalar(u8, buf[0..len], '\n');
        while (iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
                const k = std.mem.trim(u8, trimmed[0..eq], " \t");
                const v = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
                if (ConfigKey.fromString(k)) |key| {
                    if (validate(key, v)) {
                        self.values[@intFromEnum(key)] = try self.allocator.dupe(u8, v);
                    }
                }
            }
        }
    }

    /// Load from environment variables (KRILLCLAW_ prefix).
    pub fn loadEnv(self: *ConfigManager) !void {
        inline for (std.meta.fields(ConfigKey)) |f| {
            const key: ConfigKey = @enumFromInt(f.value);
            const env_name = "KRILLCLAW_" ++ comptime blk: {
                var upper: [f.name.len]u8 = undefined;
                for (f.name, 0..) |c, i| upper[i] = std.ascii.toUpper(c);
                break :blk upper;
            };
            if (std.posix.getenv(env_name)) |val| {
                if (validate(key, val)) {
                    self.values[@intFromEnum(key)] = try self.allocator.dupe(u8, val);
                }
            }
        }
    }

    /// Apply CLI-style args: --key=value or --key value.
    pub fn applyCli(self: *ConfigManager, args: []const []const u8) !void {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (!std.mem.startsWith(u8, arg, "--")) continue;
            const rest = arg[2..];
            var key_str: []const u8 = undefined;
            var val: []const u8 = undefined;
            if (std.mem.indexOfScalar(u8, rest, '=')) |eq| {
                key_str = rest[0..eq];
                val = rest[eq + 1 ..];
            } else if (i + 1 < args.len) {
                key_str = rest;
                i += 1;
                val = args[i];
            } else continue;
            if (ConfigKey.fromString(key_str)) |key| {
                try self.set(key, val);
            }
        }
    }

    /// Persist current values to disk.
    pub fn save(self: *const ConfigManager) !void {
        const file = try std.fs.cwd().createFile(self.file_path, .{});
        defer file.close();
        const w = file.writer();
        try w.writeAll("# KrillClaw Configuration\n");
        inline for (std.meta.fields(ConfigKey)) |f| {
            if (self.values[f.value]) |val| {
                try w.print("{s}={s}\n", .{ f.name, val });
            }
        }
    }

    /// Free all allocated values.
    pub fn deinit(self: *ConfigManager) void {
        for (&self.values) |*v| {
            if (v.*) |s| self.allocator.free(s);
            v.* = null;
        }
    }
};

/// Validate a key-value pair.
pub fn validate(key: ConfigKey, value: []const u8) bool {
    if (value.len == 0) return false;
    if (key == .provider) {
        for (valid_providers) |p| {
            if (std.mem.eql(u8, value, p)) return true;
        }
        return false;
    }
    return true;
}

// ============ Tests ============

test "defaults" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    try std.testing.expectEqualStrings("claude", cm.get(.provider).?);
    try std.testing.expectEqualStrings("claude-sonnet-4-20250514", cm.get(.model).?);
    try std.testing.expect(cm.get(.api_key) == null);
    try std.testing.expectEqualStrings("https://api.anthropic.com", cm.get(.endpoint_url).?);
}

test "set and get" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    try cm.set(.model, "gpt-4o");
    try std.testing.expectEqualStrings("gpt-4o", cm.get(.model).?);
}

test "validation rejects empty" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    try std.testing.expectError(error.InvalidValue, cm.set(.model, ""));
}

test "validation rejects bad provider" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    try std.testing.expectError(error.InvalidValue, cm.set(.provider, "badprovider"));
}

test "valid providers accepted" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    try cm.set(.provider, "openai");
    try std.testing.expectEqualStrings("openai", cm.get(.provider).?);
}

test "save and load roundtrip" {
    var cm = ConfigManager.init(std.testing.allocator);
    cm.file_path = "/tmp/krillclaw_test.conf";
    defer cm.deinit();
    try cm.set(.provider, "ollama");
    try cm.set(.model, "llama3");
    try cm.set(.api_key, "test-key-123");
    try cm.save();

    var cm2 = ConfigManager.init(std.testing.allocator);
    cm2.file_path = "/tmp/krillclaw_test.conf";
    defer cm2.deinit();
    try cm2.loadFile();
    try std.testing.expectEqualStrings("ollama", cm2.get(.provider).?);
    try std.testing.expectEqualStrings("llama3", cm2.get(.model).?);
    try std.testing.expectEqualStrings("test-key-123", cm2.get(.api_key).?);
    std.fs.cwd().deleteFile("/tmp/krillclaw_test.conf") catch {};
}

test "cli args override" {
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    const args = [_][]const u8{ "--provider=openai", "--model", "gpt-4o" };
    try cm.applyCli(&args);
    try std.testing.expectEqualStrings("openai", cm.get(.provider).?);
    try std.testing.expectEqualStrings("gpt-4o", cm.get(.model).?);
}

test "change callback fires" {
    const S = struct {
        var fired: bool = false;
        fn cb(_: ConfigKey, _: ?[]const u8, _: []const u8) void {
            fired = true;
        }
    };
    var cm = ConfigManager.init(std.testing.allocator);
    defer cm.deinit();
    cm.callback = S.cb;
    S.fired = false;
    try cm.set(.model, "test");
    try std.testing.expect(S.fired);
}

test "ConfigKey fromString" {
    try std.testing.expect(ConfigKey.fromString("provider") == .provider);
    try std.testing.expect(ConfigKey.fromString("api_key") == .api_key);
    try std.testing.expect(ConfigKey.fromString("bogus") == null);
}
