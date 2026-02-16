const std = @import("std");
const build_options = @import("build_options");
const types = @import("types.zig");
const config_mod = @import("config.zig");
const RuntimeConfig = @import("config_runtime.zig").RuntimeConfig;
const Agent = @import("agent.zig").Agent;

const VERSION = "0.1.0";

const Color = struct {
    const reset = "\x1b[0m";
    const cyan = "\x1b[36m";
    const yellow = "\x1b[33m";
    const dim = "\x1b[2m";
    const bold = "\x1b[1m";
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    // Load config: file -> env -> CLI
    var config = try config_mod.load(allocator);
    const one_shot = try config_mod.applyCli(&config, allocator);

    // Wrap in RuntimeConfig for runtime switching and persistence
    var rt = RuntimeConfig.init(allocator, config);

    // Validate API key
    if (rt.config.api_key.len == 0) {
        const env_name: []const u8 = switch (rt.config.provider) {
            .claude => "ANTHROPIC_API_KEY",
            .openai => "OPENAI_API_KEY",
            .ollama => "",
        };
        if (rt.config.provider == .ollama) {
            // Ollama doesn't need a key
        } else {
            try stdout.print("{s}Error: {s} not set{s}\n", .{ Color.yellow, env_name, Color.reset });
            try stdout.print("  export {s}=...\n", .{env_name});
            std.process.exit(1);
        }
    }

    // One-shot mode
    if (one_shot) |prompt| {
        var agent = Agent.init(allocator, rt.snapshot());
        defer agent.deinit();
        try agent.run(prompt);
        return;
    }

    // Interactive REPL
    try printBanner(stdout, rt.config);

    while (true) {
        try stdout.print("\n{s}>{s} ", .{ Color.cyan, Color.reset });

        const line = stdin.readUntilDelimiterAlloc(allocator, '\n', 1024 * 16) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        defer allocator.free(line);

        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // REPL commands
        if (std.mem.eql(u8, trimmed, "/quit") or
            std.mem.eql(u8, trimmed, "/exit") or
            std.mem.eql(u8, trimmed, "/q"))
        {
            break;
        }
        if (std.mem.eql(u8, trimmed, "/help")) {
            printConfigHelp(stdout) catch {};
            continue;
        }

        // Runtime config commands (/config, /config set, /config save, /config load)
        if (rt.handleCommand(trimmed, stdout) catch false) {
            continue;
        }

        // Legacy shortcuts (still work, now backed by RuntimeConfig)
        if (std.mem.startsWith(u8, trimmed, "/model ")) {
            rt.setModel(trimmed[7..]) catch |err| {
                try stdout.print("{s}Error: {}{s}\n", .{ Color.yellow, err, Color.reset });
                continue;
            };
            try stdout.print("{s}Model: {s}{s}\n", .{ Color.dim, rt.config.model, Color.reset });
            continue;
        }
        if (std.mem.eql(u8, trimmed, "/model")) {
            try stdout.print("{s}Model: {s}{s}\n", .{ Color.dim, rt.config.model, Color.reset });
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "/provider ")) {
            rt.setProvider(trimmed[10..]) catch |err| {
                try stdout.print("{s}Error: {}{s}\n", .{ Color.yellow, err, Color.reset });
                continue;
            };
            try stdout.print("{s}Provider: {s}{s}\n", .{ Color.dim, trimmed[10..], Color.reset });
            continue;
        }

        var agent = Agent.init(allocator, rt.snapshot());
        defer agent.deinit();
        agent.run(trimmed) catch |err| {
            try stdout.print("{s}Error: {}{s}\n", .{ Color.yellow, err, Color.reset });
        };
    }

    // Auto-save on exit if dirty
    if (rt.dirty) {
        rt.save() catch {};
    }

    try stdout.print("\n{s}bye{s}\n", .{ Color.dim, Color.reset });
}

fn printBanner(w: anytype, config: types.Config) !void {
    const provider_str: []const u8 = switch (config.provider) {
        .claude => "claude",
        .openai => "openai",
        .ollama => "ollama",
    };

    try w.print(
        \\
        \\{s} __   __        _         ___  _
        \\ \ \ / /___  __| |_ ___  / __|| | __ ___ __ __
        \\  \ V // _ \/ _|  _/ _ \| (__ | |/ _` \ V  V /
        \\   |_| \___/\__|\__\___/ \___||_|\__,_|\_/\_/
        \\{s}
        \\ {s}v{s} — the world's smallest coding agent{s}
        \\
        \\ Provider: {s}  Model: {s}
        \\ Commands: /help /quit /config /model <name> /provider <name>
        \\
    , .{
        Color.cyan,
        Color.reset,
        Color.dim,
        VERSION,
        Color.reset,
        provider_str,
        config.model,
    });
}

fn printConfigHelp(w: anytype) !void {
    try w.print(
        \\
        \\Commands:
        \\  /help                  Show this help
        \\  /quit, /exit, /q       Exit
        \\  /model [NAME]          Show or set model
        \\  /provider NAME         Set provider (claude, openai, ollama)
        \\  /config                Show current configuration
        \\  /config set KEY VALUE  Set a config value at runtime
        \\  /config save           Save config to .yoctoclaw.json
        \\  /config load           Reload config from .yoctoclaw.json
        \\
        \\Config keys: provider, model, api_key, base_url, max_tokens,
        \\  max_turns, streaming, wifi_ssid, wifi_password, transport
        \\
    , .{});
}

// Pull in all modules for testing
test {
    _ = @import("types.zig");
    _ = @import("json.zig");
    _ = @import("api.zig");
    _ = @import("stream.zig");
    _ = @import("tools.zig");
    _ = @import("context.zig");
    _ = @import("config.zig");
    _ = @import("config_runtime.zig");
    _ = @import("transport.zig");
    _ = @import("arena.zig");
    if (build_options.enable_ble) {
        _ = @import("ble.zig");
    }
    if (build_options.enable_serial) {
        _ = @import("serial.zig");
    }
}
