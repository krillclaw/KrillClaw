const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

/// Configuration change event — tells subscribers what changed.
pub const ConfigChange = enum {
    provider,
    model,
    api_key,
    base_url,
    max_tokens,
    max_turns,
    streaming,
    system_prompt,
    wifi_ssid,
    wifi_password,
    transport,
    serial_port,
    ble_device,
    serial_baud,
};

/// Callback type for config change notifications.
pub const ChangeCallback = *const fn (change: ConfigChange, ctx: *anyopaque) void;

/// Subscriber slot for change notifications.
const Subscriber = struct {
    callback: ChangeCallback,
    ctx: *anyopaque,
};

/// Runtime configuration manager.
///
/// Wraps types.Config with:
///   - Runtime switching (set any field, get notified)
///   - Persistence (save/load JSON to disk)
///   - Validation (before applying changes)
///   - Change notification (so agent loop can reconnect)
///
/// Priority: CLI args > env vars > config file > compile-time defaults
/// (Load priority is handled by config.zig; this manages runtime changes)
pub const RuntimeConfig = struct {
    config: types.Config,
    allocator: std.mem.Allocator,
    config_path: []const u8,
    dirty: bool = false,
    subscribers: [8]?Subscriber = .{null} ** 8,

    pub fn init(allocator: std.mem.Allocator, config: types.Config) RuntimeConfig {
        return .{
            .config = config,
            .allocator = allocator,
            .config_path = ".yoctoclaw.json",
        };
    }

    /// Subscribe to config changes. Returns subscriber index for unsubscribe.
    pub fn subscribe(self: *RuntimeConfig, callback: ChangeCallback, ctx: *anyopaque) ?usize {
        var i: usize = 0;
        while (i < self.subscribers.len) : (i += 1) {
            if (self.subscribers[i] == null) {
                self.subscribers[i] = .{ .callback = callback, .ctx = ctx };
                return i;
            }
        }
        return null;
    }

    /// Unsubscribe from config changes.
    pub fn unsubscribe(self: *RuntimeConfig, index: usize) void {
        if (index < self.subscribers.len) {
            self.subscribers[index] = null;
        }
    }

    fn notify(self: *RuntimeConfig, change: ConfigChange) void {
        for (self.subscribers) |slot| {
            if (slot) |sub| {
                sub.callback(change, sub.ctx);
            }
        }
    }

    // --- Setters with validation and notification ---

    pub fn setProvider(self: *RuntimeConfig, provider_str: []const u8) !void {
        const provider = parseProvider(provider_str) orelse return error.InvalidProvider;
        self.config.provider = provider;
        self.dirty = true;
        self.notify(.provider);
    }

    pub fn setModel(self: *RuntimeConfig, model: []const u8) !void {
        if (model.len == 0) return error.InvalidModel;
        if (model.len > 256) return error.InvalidModel;
        self.config.model = try self.allocator.dupe(u8, model);
        self.dirty = true;
        self.notify(.model);
    }

    pub fn setApiKey(self: *RuntimeConfig, key: []const u8) !void {
        if (key.len == 0) return error.InvalidApiKey;
        self.config.api_key = try self.allocator.dupe(u8, key);
        self.dirty = true;
        self.notify(.api_key);
    }

    pub fn setBaseUrl(self: *RuntimeConfig, url: []const u8) !void {
        if (url.len > 0 and !std.mem.startsWith(u8, url, "http")) return error.InvalidUrl;
        self.config.base_url = if (url.len > 0) try self.allocator.dupe(u8, url) else null;
        self.dirty = true;
        self.notify(.base_url);
    }

    pub fn setMaxTokens(self: *RuntimeConfig, tokens: u32) !void {
        if (tokens == 0 or tokens > 1000000) return error.InvalidMaxTokens;
        self.config.max_tokens = tokens;
        self.dirty = true;
        self.notify(.max_tokens);
    }

    pub fn setMaxTurns(self: *RuntimeConfig, turns: u32) !void {
        if (turns == 0 or turns > 1000) return error.InvalidMaxTurns;
        self.config.max_turns = turns;
        self.dirty = true;
        self.notify(.max_turns);
    }

    pub fn setStreaming(self: *RuntimeConfig, streaming: bool) void {
        self.config.streaming = streaming;
        self.dirty = true;
        self.notify(.streaming);
    }

    pub fn setWifiSsid(self: *RuntimeConfig, ssid: []const u8) !void {
        if (ssid.len == 0 or ssid.len > 32) return error.InvalidWifiSsid;
        self.config.wifi_ssid = try self.allocator.dupe(u8, ssid);
        self.dirty = true;
        self.notify(.wifi_ssid);
    }

    pub fn setWifiPassword(self: *RuntimeConfig, password: []const u8) !void {
        if (password.len > 63) return error.InvalidWifiPassword;
        self.config.wifi_password = if (password.len > 0) try self.allocator.dupe(u8, password) else null;
        self.dirty = true;
        self.notify(.wifi_password);
    }

    pub fn setTransport(self: *RuntimeConfig, transport_str: []const u8) !void {
        const t = parseTransport(transport_str) orelse return error.InvalidTransport;
        self.config.transport = t;
        self.dirty = true;
        self.notify(.transport);
    }

    // --- Persistence ---

    /// Save current config to JSON file.
    pub fn save(self: *RuntimeConfig) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        const w = buf.writer();

        try w.writeAll("{\n");
        try writeJsonField(w, "provider", providerStr(self.config.provider));
        try w.writeAll(",\n");
        try writeJsonField(w, "model", self.config.model);

        if (self.config.api_key.len > 0) {
            try w.writeAll(",\n");
            try writeJsonField(w, "api_key", self.config.api_key);
        }
        if (self.config.base_url) |url| {
            try w.writeAll(",\n");
            try writeJsonField(w, "base_url", url);
        }

        try w.writeAll(",\n  \"max_tokens\": ");
        try w.print("{d}", .{self.config.max_tokens});
        try w.writeAll(",\n  \"max_turns\": ");
        try w.print("{d}", .{self.config.max_turns});
        try w.writeAll(",\n  \"streaming\": ");
        try w.print("{}", .{self.config.streaming});

        if (self.config.wifi_ssid) |ssid| {
            try w.writeAll(",\n");
            try writeJsonField(w, "wifi_ssid", ssid);
        }
        if (self.config.wifi_password) |pass| {
            try w.writeAll(",\n");
            try writeJsonField(w, "wifi_password", pass);
        }

        try w.writeAll(",\n");
        try writeJsonField(w, "transport", transportStr(self.config.transport));

        if (self.config.serial_port) |port| {
            try w.writeAll(",\n");
            try writeJsonField(w, "serial_port", port);
        }
        if (self.config.ble_device) |dev| {
            try w.writeAll(",\n");
            try writeJsonField(w, "ble_device", dev);
        }
        try w.writeAll(",\n  \"serial_baud\": ");
        try w.print("{d}", .{self.config.serial_baud});

        try w.writeAll("\n}\n");

        const file = try std.fs.cwd().createFile(self.config_path, .{});
        defer file.close();
        try file.writeAll(buf.items);

        self.dirty = false;
    }

    /// Load config from JSON file (merges on top of current config).
    pub fn load(self: *RuntimeConfig) !void {
        const file = std.fs.cwd().openFile(self.config_path, .{}) catch return;
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 64 * 1024);
        defer self.allocator.free(content);

        self.applyJson(content);
    }

    /// Apply JSON content to config (for both file load and programmatic use).
    pub fn applyJson(self: *RuntimeConfig, content: []const u8) void {
        if (json.extractString(content, "provider")) |p| {
            if (parseProvider(p)) |prov| {
                self.config.provider = prov;
            }
        }
        if (json.extractString(content, "model")) |m| {
            self.config.model = self.allocator.dupe(u8, m) catch return;
        }
        if (json.extractString(content, "api_key")) |k| {
            self.config.api_key = self.allocator.dupe(u8, k) catch return;
        }
        if (json.extractString(content, "base_url")) |u| {
            self.config.base_url = self.allocator.dupe(u8, u) catch return;
        }
        if (json.extractInt(content, "max_tokens")) |mt| {
            self.config.max_tokens = mt;
        }
        if (json.extractInt(content, "max_turns")) |mt| {
            self.config.max_turns = mt;
        }
        if (json.extractBool(content, "streaming")) |s| {
            self.config.streaming = s;
        }
        if (json.extractString(content, "wifi_ssid")) |ssid| {
            self.config.wifi_ssid = self.allocator.dupe(u8, ssid) catch return;
        }
        if (json.extractString(content, "wifi_password")) |pass| {
            self.config.wifi_password = self.allocator.dupe(u8, pass) catch return;
        }
        if (json.extractString(content, "transport")) |t| {
            if (parseTransport(t)) |tr| {
                self.config.transport = tr;
            }
        }
        if (json.extractString(content, "serial_port")) |sp| {
            self.config.serial_port = self.allocator.dupe(u8, sp) catch return;
        }
        if (json.extractString(content, "ble_device")) |bd| {
            self.config.ble_device = self.allocator.dupe(u8, bd) catch return;
        }
        if (json.extractInt(content, "serial_baud")) |baud| {
            self.config.serial_baud = baud;
        }
    }

    /// Get a snapshot of current config (for passing to Agent, etc.)
    pub fn snapshot(self: *const RuntimeConfig) types.Config {
        return self.config;
    }

    /// Format a human-readable summary of current config.
    pub fn printStatus(self: *const RuntimeConfig, w: anytype) !void {
        try w.writeAll("Configuration:\n");
        try w.print("  provider:    {s}\n", .{providerStr(self.config.provider)});
        try w.print("  model:       {s}\n", .{self.config.model});
        if (self.config.api_key.len > 4) {
            try w.writeAll("  api_key:     ****");
            try w.writeAll(self.config.api_key[self.config.api_key.len - 4 ..]);
            try w.writeByte(0x0a);
        } else if (self.config.api_key.len > 0) {
            try w.writeAll("  api_key:     ****\n");
        } else {
            try w.writeAll("  api_key:     (not set)\n");
        }
        try w.print("  max_tokens:  {d}\n", .{self.config.max_tokens});
        try w.print("  max_turns:   {d}\n", .{self.config.max_turns});
        try w.print("  streaming:   {}\n", .{self.config.streaming});
        try w.print("  transport:   {s}\n", .{transportStr(self.config.transport)});
        if (self.config.base_url) |url| try w.print("  base_url:    {s}\n", .{url});
        if (self.config.wifi_ssid) |ssid| try w.print("  wifi_ssid:   {s}\n", .{ssid});
        if (self.config.wifi_password != null) try w.writeAll("  wifi_pass:   ****\n");
        if (self.config.serial_port) |port| try w.print("  serial_port: {s}\n", .{port});
        if (self.config.ble_device) |dev| try w.print("  ble_device:  {s}\n", .{dev});
        try w.print("  serial_baud: {d}\n", .{self.config.serial_baud});
        if (self.dirty) try w.writeAll("  (unsaved changes)\n");
    }

    /// Handle a /config REPL command. Returns true if handled.
    pub fn handleCommand(self: *RuntimeConfig, line: []const u8, w: anytype) !bool {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (std.mem.eql(u8, trimmed, "/config")) {
            try self.printStatus(w);
            return true;
        }
        if (std.mem.eql(u8, trimmed, "/config save")) {
            self.save() catch |err| {
                try w.print("Error saving config: {}\n", .{err});
                return true;
            };
            try w.print("Config saved to {s}\n", .{self.config_path});
            return true;
        }
        if (std.mem.eql(u8, trimmed, "/config load")) {
            self.load() catch |err| {
                try w.print("Error loading config: {}\n", .{err});
                return true;
            };
            try w.writeAll("Config loaded\n");
            return true;
        }

        // /config set <key> <value>
        if (std.mem.startsWith(u8, trimmed, "/config set ")) {
            const rest = trimmed[12..];
            const space = std.mem.indexOf(u8, rest, " ") orelse {
                try w.writeAll("Usage: /config set <key> <value>\n");
                return true;
            };
            const key = rest[0..space];
            const value = std.mem.trim(u8, rest[space + 1 ..], &std.ascii.whitespace);

            self.setByName(key, value) catch |err| {
                try w.print("Error setting {s}: {}\n", .{ key, err });
                return true;
            };
            try w.print("{s} = {s}\n", .{ key, value });
            return true;
        }

        return false;
    }

    /// Set a config value by name (for REPL and serial CLI).
    pub fn setByName(self: *RuntimeConfig, key: []const u8, value: []const u8) !void {
        if (std.mem.eql(u8, key, "provider")) {
            try self.setProvider(value);
        } else if (std.mem.eql(u8, key, "model")) {
            try self.setModel(value);
        } else if (std.mem.eql(u8, key, "api_key")) {
            try self.setApiKey(value);
        } else if (std.mem.eql(u8, key, "base_url")) {
            try self.setBaseUrl(value);
        } else if (std.mem.eql(u8, key, "max_tokens")) {
            const v = std.fmt.parseInt(u32, value, 10) catch return error.InvalidValue;
            try self.setMaxTokens(v);
        } else if (std.mem.eql(u8, key, "max_turns")) {
            const v = std.fmt.parseInt(u32, value, 10) catch return error.InvalidValue;
            try self.setMaxTurns(v);
        } else if (std.mem.eql(u8, key, "streaming")) {
            self.setStreaming(std.mem.eql(u8, value, "true"));
        } else if (std.mem.eql(u8, key, "wifi_ssid")) {
            try self.setWifiSsid(value);
        } else if (std.mem.eql(u8, key, "wifi_password")) {
            try self.setWifiPassword(value);
        } else if (std.mem.eql(u8, key, "transport")) {
            try self.setTransport(value);
        } else {
            return error.UnknownConfigKey;
        }
    }
};

// --- Helpers ---

fn parseProvider(s: []const u8) ?types.Provider {
    if (std.mem.eql(u8, s, "claude")) return .claude;
    if (std.mem.eql(u8, s, "openai")) return .openai;
    if (std.mem.eql(u8, s, "ollama")) return .ollama;
    return null;
}

fn parseTransport(s: []const u8) ?types.TransportKind {
    if (std.mem.eql(u8, s, "http")) return .http;
    if (std.mem.eql(u8, s, "ble")) return .ble;
    if (std.mem.eql(u8, s, "serial")) return .serial;
    return null;
}

fn providerStr(p: types.Provider) []const u8 {
    return switch (p) {
        .claude => "claude",
        .openai => "openai",
        .ollama => "ollama",
    };
}

fn transportStr(t: types.TransportKind) []const u8 {
    return switch (t) {
        .http => "http",
        .ble => "ble",
        .serial => "serial",
    };
}

fn writeJsonField(w: anytype, key: []const u8, value: []const u8) !void {
    try w.print("  \"{s}\": \"{s}\"", .{ key, value });
}

// --- Tests ---

test "RuntimeConfig set and get" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});

    try rc.setProvider("openai");
    try std.testing.expectEqual(types.Provider.openai, rc.config.provider);
    try std.testing.expect(rc.dirty);

    try rc.setModel("gpt-4o");
    try std.testing.expectEqualStrings("gpt-4o", rc.config.model);
    defer alloc.free(@constCast(rc.config.model));

    try rc.setMaxTokens(4096);
    try std.testing.expectEqual(@as(u32, 4096), rc.config.max_tokens);
}

test "RuntimeConfig validation rejects invalid values" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});

    try std.testing.expectError(error.InvalidProvider, rc.setProvider("invalid"));
    try std.testing.expectError(error.InvalidModel, rc.setModel(""));
    try std.testing.expectError(error.InvalidMaxTokens, rc.setMaxTokens(0));
    try std.testing.expectError(error.InvalidMaxTokens, rc.setMaxTokens(2000000));
    try std.testing.expectError(error.InvalidUrl, rc.setBaseUrl("not-a-url"));
    try std.testing.expectError(error.InvalidWifiSsid, rc.setWifiSsid(""));
}

test "RuntimeConfig setByName" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});

    try rc.setByName("provider", "ollama");
    try std.testing.expectEqual(types.Provider.ollama, rc.config.provider);

    try rc.setByName("max_tokens", "2048");
    try std.testing.expectEqual(@as(u32, 2048), rc.config.max_tokens);

    try std.testing.expectError(error.UnknownConfigKey, rc.setByName("nonexistent", "value"));
}

test "RuntimeConfig change notification" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});

    const State = struct {
        var last_change: ?ConfigChange = null;
        fn callback(change: ConfigChange, _: *anyopaque) void {
            last_change = change;
        }
    };

    var dummy: u8 = 0;
    const idx = rc.subscribe(State.callback, @ptrCast(&dummy));
    try std.testing.expect(idx != null);

    try rc.setProvider("openai");
    try std.testing.expectEqual(ConfigChange.provider, State.last_change.?);

    try rc.setMaxTokens(1000);
    try std.testing.expectEqual(ConfigChange.max_tokens, State.last_change.?);

    rc.unsubscribe(idx.?);
    State.last_change = null;
    try rc.setMaxTurns(10);
    try std.testing.expect(State.last_change == null);
}

test "RuntimeConfig applyJson" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});

    rc.applyJson("{\"provider\":\"openai\",\"model\":\"gpt-4o\",\"max_tokens\":2048,\"streaming\":false}");

    try std.testing.expectEqual(types.Provider.openai, rc.config.provider);
    try std.testing.expectEqual(@as(u32, 2048), rc.config.max_tokens);
    try std.testing.expectEqual(false, rc.config.streaming);
    defer alloc.free(@constCast(rc.config.model));
    try std.testing.expectEqualStrings("gpt-4o", rc.config.model);
}

test "RuntimeConfig save and load roundtrip" {
    const alloc = std.testing.allocator;
    var rc = RuntimeConfig.init(alloc, types.Config{});
    rc.config_path = "/tmp/yoctoclaw_test_config.json";

    try rc.setProvider("openai");
    try rc.setMaxTokens(4096);
    rc.setStreaming(false);
    try rc.save();

    // Load into fresh config
    var rc2 = RuntimeConfig.init(alloc, types.Config{});
    rc2.config_path = "/tmp/yoctoclaw_test_config.json";
    try rc2.load();

    try std.testing.expectEqual(types.Provider.openai, rc2.config.provider);
    try std.testing.expectEqual(@as(u32, 4096), rc2.config.max_tokens);
    try std.testing.expectEqual(false, rc2.config.streaming);

    // Free allocated strings from applyJson
    alloc.free(@constCast(rc2.config.model));

    // Cleanup
    std.fs.cwd().deleteFile("/tmp/yoctoclaw_test_config.json") catch {};
}
