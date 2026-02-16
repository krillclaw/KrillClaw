const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

/// Load configuration from environment variables and optional config file.
///
/// Priority: CLI flags > env vars > config file > defaults
pub fn load(allocator: std.mem.Allocator) !types.Config {
    var config = types.Config{};

    // Try loading config file
    if (loadConfigFile(allocator)) |file_config| {
        config = mergeConfig(config, file_config);
    }

    // Environment variables override
    if (getEnv(allocator, "ANTHROPIC_API_KEY")) |key| config.api_key = key;
    if (getEnv(allocator, "OPENAI_API_KEY")) |key| {
        config.api_key = key;
        config.provider = .openai;
    }
    if (getEnv(allocator, "YOCTOCLAW_MODEL")) |m| config.model = m;
    if (getEnv(allocator, "YOCTOCLAW_PROVIDER")) |p| {
        if (std.mem.eql(u8, p, "claude")) config.provider = .claude;
        if (std.mem.eql(u8, p, "openai")) config.provider = .openai;
        if (std.mem.eql(u8, p, "ollama")) config.provider = .ollama;
    }
    if (getEnv(allocator, "YOCTOCLAW_MAX_TOKENS")) |mt| {
        config.max_tokens = std.fmt.parseInt(u32, mt, 10) catch config.max_tokens;
    }
    if (getEnv(allocator, "YOCTOCLAW_BASE_URL")) |url| config.base_url = url;
    if (getEnv(allocator, "YOCTOCLAW_SYSTEM_PROMPT")) |sp| config.system_prompt = sp;
    if (getEnv(allocator, "YOCTOCLAW_TRANSPORT")) |t| {
        if (std.mem.eql(u8, t, "ble")) config.transport = .ble;
        if (std.mem.eql(u8, t, "serial")) config.transport = .serial;
    }
    if (getEnv(allocator, "YOCTOCLAW_SERIAL_PORT")) |sp| config.serial_port = sp;
    if (getEnv(allocator, "YOCTOCLAW_BLE_DEVICE")) |bd| config.ble_device = bd;

    return config;
}

/// Apply CLI arguments over existing config.
pub fn applyCli(config: *types.Config, allocator: std.mem.Allocator) !?[]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    var prompt: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            const stdout = std.fs.File.stdout().deprecatedWriter();
            try stdout.print("yoctoclaw 0.1.0\n", .{});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            config.model = args.next() orelse {
                std.debug.print("Error: --model requires a value\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--prompt")) {
            prompt = args.next() orelse {
                std.debug.print("Error: --prompt requires a value\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--provider")) {
            const prov = args.next() orelse {
                std.debug.print("Error: --provider requires a value\n", .{});
                std.process.exit(1);
            };
            if (std.mem.eql(u8, prov, "claude")) config.provider = .claude;
            if (std.mem.eql(u8, prov, "openai")) config.provider = .openai;
            if (std.mem.eql(u8, prov, "ollama")) {
                config.provider = .ollama;
                config.streaming = false; // Ollama streaming format differs
            }
        } else if (std.mem.eql(u8, arg, "--base-url")) {
            config.base_url = args.next();
        } else if (std.mem.eql(u8, arg, "--no-stream")) {
            config.streaming = false;
        } else if (std.mem.eql(u8, arg, "--transport")) {
            const t = args.next() orelse "http";
            if (std.mem.eql(u8, t, "ble")) config.transport = .ble;
            if (std.mem.eql(u8, t, "serial")) config.transport = .serial;
        } else if (std.mem.eql(u8, arg, "--serial-port")) {
            config.serial_port = args.next();
            config.transport = .serial;
        } else if (std.mem.eql(u8, arg, "--ble-device")) {
            config.ble_device = args.next();
            config.transport = .ble;
        } else if (arg[0] != '-') {
            prompt = arg;
        }
    }

    return prompt;
}

fn loadConfigFile(allocator: std.mem.Allocator) ?types.Config {
    // Try .yoctoclaw.json in current directory
    const paths = [_][]const u8{
        ".yoctoclaw.json",
    };

    for (paths) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 64) catch continue;
        defer allocator.free(content);

        var config = types.Config{};

        if (json.extractString(content, "model")) |m| config.model = allocator.dupe(u8, m) catch continue;
        if (json.extractString(content, "provider")) |p| {
            if (std.mem.eql(u8, p, "claude")) config.provider = .claude;
            if (std.mem.eql(u8, p, "openai")) config.provider = .openai;
            if (std.mem.eql(u8, p, "ollama")) config.provider = .ollama;
        }
        if (json.extractInt(content, "max_tokens")) |mt| config.max_tokens = mt;
        if (json.extractInt(content, "max_turns")) |mt| config.max_turns = mt;
        if (json.extractString(content, "system_prompt")) |sp| config.system_prompt = allocator.dupe(u8, sp) catch continue;
        if (json.extractString(content, "base_url")) |url| config.base_url = allocator.dupe(u8, url) catch continue;
        if (json.extractBool(content, "streaming")) |s| config.streaming = s;

        return config;
    }

    return null;
}

fn mergeConfig(base: types.Config, overlay: types.Config) types.Config {
    var result = base;
    if (overlay.model.len > 0 and !std.mem.eql(u8, overlay.model, base.model)) result.model = overlay.model;
    if (overlay.provider != base.provider) result.provider = overlay.provider;
    if (overlay.max_tokens != base.max_tokens) result.max_tokens = overlay.max_tokens;
    if (overlay.max_turns != base.max_turns) result.max_turns = overlay.max_turns;
    if (overlay.base_url != null) result.base_url = overlay.base_url;
    if (!overlay.streaming) result.streaming = overlay.streaming;
    return result;
}

fn getEnv(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(allocator, name) catch null;
}

pub fn printHelp() void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    stdout.print(
        \\
        \\YoctoClaw — the world's smallest coding agent
        \\
        \\Usage:
        \\  yoctoclaw                        Interactive REPL
        \\  yoctoclaw "fix the bug"          One-shot mode
        \\  yoctoclaw -p "add tests"         One-shot mode (explicit)
        \\
        \\Options:
        \\  -m, --model MODEL       Model name (default: claude-sonnet-4-5-20250929)
        \\  -p, --prompt TEXT       Run a single prompt and exit
        \\  --provider PROVIDER     claude, openai, or ollama
        \\  --base-url URL          Custom API base URL
        \\  --no-stream             Disable streaming
        \\  --transport TYPE        http, ble, or serial
        \\  --serial-port PATH      Serial port (e.g. /dev/ttyUSB0)
        \\  --ble-device ADDR       BLE device address
        \\  -v, --version           Show version
        \\  -h, --help              Show this help
        \\
        \\Environment:
        \\  ANTHROPIC_API_KEY       Claude API key
        \\  OPENAI_API_KEY          OpenAI API key (auto-selects openai provider)
        \\  YOCTOCLAW_MODEL          Model override
        \\  YOCTOCLAW_PROVIDER       Provider override
        \\  YOCTOCLAW_BASE_URL       API base URL override
        \\  YOCTOCLAW_SYSTEM_PROMPT  System prompt override
        \\
        \\Config file: .yoctoclaw.json (current dir)
        \\
    , .{}) catch {};
}
