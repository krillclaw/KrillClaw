//! IoT profile tools — communicates with Python bridge via structured JSON over stdin/stdout.
//! Policy: no bash, no arbitrary file writes, rate-limited bridge calls.
const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");
const build_options = @import("build_options");

pub const ToolResult = struct {
    output: []const u8,
    is_error: bool,
};

pub const tool_definitions = [_]types.ToolDef{
    .{ .name = "publish_mqtt", .description = "Publish a message to an MQTT topic.", .input_schema =
        \\{"type":"object","properties":{"topic":{"type":"string"},"payload":{"type":"string"},"qos":{"type":"integer","default":0}},"required":["topic","payload"]}
    },
    .{ .name = "subscribe_mqtt", .description = "Subscribe to an MQTT topic and return the next message (with timeout).", .input_schema =
        \\{"type":"object","properties":{"topic":{"type":"string"},"timeout_ms":{"type":"integer","default":5000}},"required":["topic"]}
    },
    .{ .name = "http_request", .description = "Make an HTTP request (GET/POST/PUT/DELETE).", .input_schema =
        \\{"type":"object","properties":{"method":{"type":"string","enum":["GET","POST","PUT","DELETE"]},"url":{"type":"string"},"body":{"type":"string"},"headers":{"type":"object"}},"required":["method","url"]}
    },
    .{ .name = "kv_get", .description = "Get a value from the key-value store.", .input_schema =
        \\{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}
    },
    .{ .name = "kv_set", .description = "Set a value in the key-value store.", .input_schema =
        \\{"type":"object","properties":{"key":{"type":"string"},"value":{"type":"string"}},"required":["key","value"]}
    },
    .{ .name = "device_info", .description = "Get device information and status.", .input_schema =
        \\{"type":"object","properties":{},"required":[]}
    },
};

/// Rate limiter: max 30 bridge calls per minute
var call_timestamps: [30]i64 = [_]i64{0} ** 30;
var call_idx: usize = 0;

fn checkRateLimit() bool {
    const now = std.time.timestamp();
    const oldest = call_timestamps[call_idx];
    if (oldest != 0 and (now - oldest) < 60) return false;
    call_timestamps[call_idx] = now;
    call_idx = (call_idx + 1) % 30;
    return true;
}

/// Validate KV key: alphanumeric, dashes, underscores, dots only. No path traversal.
fn isValidKvKey(key: []const u8) bool {
    if (key.len == 0 or key.len > 128) return false;
    if (std.mem.indexOf(u8, key, "..") != null) return false;
    if (std.mem.indexOf(u8, key, "/") != null) return false;
    for (key) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '.') return false;
    }
    return true;
}

pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    // Policy: no bash, no file writes
    if (std.mem.eql(u8, tool.name, "bash")) return .{ .output = "bash disabled in IoT profile", .is_error = true };
    if (std.mem.eql(u8, tool.name, "write_file")) return .{ .output = "write_file disabled in IoT profile", .is_error = true };

    // Pure Zig tools (no bridge needed)
    if (std.mem.eql(u8, tool.name, "kv_get")) return executeKvGet(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "kv_set")) return executeKvSet(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "device_info")) return executeDeviceInfo(allocator);

    // Bridge tools — rate limited
    if (!checkRateLimit()) return .{ .output = "Rate limit exceeded (30/min)", .is_error = true };

    if (std.mem.eql(u8, tool.name, "publish_mqtt")) {
        const topic = json.extractString(tool.input_raw, "topic") orelse
            return .{ .output = "Missing 'topic' parameter", .is_error = true };
        const payload = json.extractString(tool.input_raw, "payload") orelse
            return .{ .output = "Missing 'payload' parameter", .is_error = true };
        // Build JSON safely with proper escaping
        var buf: std.ArrayList(u8) = .{};
        const w = buf.writer();
        w.writeAll("{\"action\":\"mqtt_publish\",\"topic\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, topic) catch return .{ .output = "JSON build error", .is_error = true };
        w.writeAll("\",\"payload\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, payload) catch return .{ .output = "JSON build error", .is_error = true };
        w.writeAll("\"}") catch return .{ .output = "JSON build error", .is_error = true };
        const bridge_json = buf.toOwnedSlice(allocator) catch return .{ .output = "JSON build error", .is_error = true };
        return bridgeCall(allocator, bridge_json);
    }

    if (std.mem.eql(u8, tool.name, "subscribe_mqtt")) {
        const topic = json.extractString(tool.input_raw, "topic") orelse
            return .{ .output = "Missing 'topic' parameter", .is_error = true };
        const timeout = json.extractInt(tool.input_raw, "timeout_ms") orelse 5000;
        // Build JSON safely with proper escaping
        var buf: std.ArrayList(u8) = .{};
        const w = buf.writer();
        w.writeAll("{\"action\":\"mqtt_subscribe\",\"topic\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, topic) catch return .{ .output = "JSON build error", .is_error = true };
        w.print("\",\"timeout_ms\":{d}}}", .{timeout}) catch return .{ .output = "JSON build error", .is_error = true };
        const bridge_json = buf.toOwnedSlice(allocator) catch return .{ .output = "JSON build error", .is_error = true };
        return bridgeCall(allocator, bridge_json);
    }

    if (std.mem.eql(u8, tool.name, "http_request")) {
        const method = json.extractString(tool.input_raw, "method") orelse
            return .{ .output = "Missing 'method' parameter", .is_error = true };
        const url = json.extractString(tool.input_raw, "url") orelse
            return .{ .output = "Missing 'url' parameter", .is_error = true };
        const body = json.extractString(tool.input_raw, "body") orelse "";
        // Build JSON safely with proper escaping
        var buf: std.ArrayList(u8) = .{};
        const w = buf.writer();
        w.writeAll("{\"action\":\"http_request\",\"method\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, method) catch return .{ .output = "JSON build error", .is_error = true };
        w.writeAll("\",\"url\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, url) catch return .{ .output = "JSON build error", .is_error = true };
        w.writeAll("\",\"body\":\"") catch return .{ .output = "JSON build error", .is_error = true };
        json.writeEscaped(w, body) catch return .{ .output = "JSON build error", .is_error = true };
        w.writeAll("\"}") catch return .{ .output = "JSON build error", .is_error = true };
        const bridge_json = buf.toOwnedSlice(allocator) catch return .{ .output = "JSON build error", .is_error = true };
        return bridgeCall(allocator, bridge_json);
    }

    return .{ .output = "Unknown tool", .is_error = true };
}

/// KV Get — read file from .yoctoclaw/kv/<key>
fn executeKvGet(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const key = json.extractString(input, "key") orelse
        return .{ .output = "Missing 'key' parameter", .is_error = true };
    if (!isValidKvKey(key)) return .{ .output = "Invalid key (alphanumeric, dash, underscore, dot only)", .is_error = true };

    const path = std.fmt.allocPrint(allocator, ".yoctoclaw/kv/{s}", .{key}) catch
        return .{ .output = "Path build error", .is_error = true };
    const file = std.fs.cwd().openFile(path, .{}) catch
        return .{ .output = "Key not found", .is_error = true };
    defer file.close();
    const content = file.readToEndAlloc(allocator, 1024 * 64) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Read error: {}", .{err}) catch "read error";
        return .{ .output = msg, .is_error = true };
    };
    return .{ .output = if (content.len == 0) "(empty)" else content, .is_error = false };
}

/// KV Set — write file to .yoctoclaw/kv/<key>
fn executeKvSet(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const key = json.extractString(input, "key") orelse
        return .{ .output = "Missing 'key' parameter", .is_error = true };
    const value = json.extractString(input, "value") orelse
        return .{ .output = "Missing 'value' parameter", .is_error = true };
    if (!isValidKvKey(key)) return .{ .output = "Invalid key (alphanumeric, dash, underscore, dot only)", .is_error = true };

    std.fs.cwd().makePath(".yoctoclaw/kv") catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot create KV dir: {}", .{err}) catch "dir error";
        return .{ .output = msg, .is_error = true };
    };

    const path = std.fmt.allocPrint(allocator, ".yoctoclaw/kv/{s}", .{key}) catch
        return .{ .output = "Path build error", .is_error = true };
    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot create '{s}': {}", .{ path, err }) catch "create error";
        return .{ .output = msg, .is_error = true };
    };
    defer file.close();
    const unescaped = json.unescape(allocator, value) catch value;
    file.writeAll(unescaped) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Write error: {}", .{err}) catch "write error";
        return .{ .output = msg, .is_error = true };
    };
    const msg = std.fmt.allocPrint(allocator, "Stored {d} bytes at key '{s}'", .{ unescaped.len, key }) catch "stored";
    return .{ .output = msg, .is_error = false };
}

/// Device info — pure Zig, no bridge needed
fn executeDeviceInfo(allocator: std.mem.Allocator) ToolResult {
    var info: std.ArrayList(u8) = .{};
    const w = info.writer();

    // Hostname
    w.writeAll("{\"hostname\":\"") catch {};
    if (std.process.Child.run(.{ .allocator = allocator, .argv = &.{"hostname"}, .max_output_bytes = 256 })) |r| {
        w.writeAll(std.mem.trimRight(u8, r.stdout, "\n\r ")) catch {};
    } else |_| {
        w.writeAll("unknown") catch {};
    }

    // OS
    w.writeAll("\",\"os\":\"") catch {};
    if (std.process.Child.run(.{ .allocator = allocator, .argv = &.{ "uname", "-srm" }, .max_output_bytes = 256 })) |r| {
        w.writeAll(std.mem.trimRight(u8, r.stdout, "\n\r ")) catch {};
    } else |_| {
        w.writeAll("unknown") catch {};
    }

    // Uptime
    w.writeAll("\",\"uptime\":\"") catch {};
    if (std.process.Child.run(.{ .allocator = allocator, .argv = &.{"uptime"}, .max_output_bytes = 256 })) |r| {
        const up = std.mem.trimRight(u8, r.stdout, "\n\r ");
        // Escape for JSON
        for (up) |c| {
            if (c == '"') { w.writeAll("\\\"") catch {}; } else if (c == '\\') { w.writeAll("\\\\") catch {}; } else { w.writeByte(c) catch {}; }
        }
    } else |_| {}

    // Memory
    w.writeAll("\",\"memory\":\"") catch {};
    if (std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", "if [ -f /proc/meminfo ]; then head -3 /proc/meminfo | tr '\\n' '; '; else sysctl -n hw.memsize 2>/dev/null; fi" },
        .max_output_bytes = 512,
    })) |r| {
        const mem = std.mem.trimRight(u8, r.stdout, "\n\r ");
        for (mem) |c| {
            if (c == '"') { w.writeAll("\\\"") catch {}; } else if (c == '\\') { w.writeAll("\\\\") catch {}; } else { w.writeByte(c) catch {}; }
        }
    } else |_| {}

    w.writeAll("\"}") catch {};
    return .{ .output = info.toOwnedSlice(allocator) catch "{\"error\":\"build failed\"}", .is_error = false };
}

/// Send structured JSON to the Python bridge via CLI argument, read response from stdout.
fn bridgeCall(allocator: std.mem.Allocator, bridge_json: []const u8) ToolResult {
    if (build_options.sandbox) {
        return .{ .output = "{\"status\":\"simulated\",\"message\":\"sandbox mode - bridge calls are simulated\"}", .is_error = false };
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", "bridge/bridge.py", "--exec-tool", bridge_json },
        .max_output_bytes = 1024 * 256,
    }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Bridge call failed: {}", .{err}) catch "bridge error";
        return .{ .output = msg, .is_error = true };
    };

    const is_err = switch (result.term) {
        .Exited => |code| code != 0,
        else => true,
    };
    const output = if (result.stdout.len > 0) result.stdout else if (result.stderr.len > 0) result.stderr else "(no output)";
    return .{ .output = output, .is_error = is_err };
}
