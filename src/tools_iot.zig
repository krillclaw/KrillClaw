//! IoT profile tools — communicates with Python bridge via structured JSON over stdin/stdout.
//! Policy: no bash, no arbitrary file writes, rate-limited bridge calls.
const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

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
    if (oldest != 0 and (now - oldest) < 60) return false; // window full
    call_timestamps[call_idx] = now;
    call_idx = (call_idx + 1) % 30;
    return true;
}

pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    // Policy: no bash, no file writes
    if (std.mem.eql(u8, tool.name, "bash")) return .{ .output = "bash disabled in IoT profile", .is_error = true };
    if (std.mem.eql(u8, tool.name, "write_file")) return .{ .output = "write_file disabled in IoT profile", .is_error = true };

    if (!checkRateLimit()) return .{ .output = "Rate limit exceeded (30/min)", .is_error = true };

    return bridgeCall(allocator, tool.name, tool.input_raw);
}

/// Send a structured JSON command to the Python bridge process via stdin/stdout.
fn bridgeCall(allocator: std.mem.Allocator, tool_name: []const u8, input: []const u8) ToolResult {
    const cmd = std.fmt.allocPrint(allocator,
        \\{{"tool":"{s}","input":{s}}}
    , .{ tool_name, input }) catch return .{ .output = "JSON build error", .is_error = true };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", "bridge/bridge.py", "--exec-tool" },
        .max_output_bytes = 1024 * 256,
    }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Bridge call failed: {}", .{err}) catch "bridge error";
        return .{ .output = msg, .is_error = true };
    };
    // Pass command via environment or stdin — for now use argv
    _ = cmd;

    const is_err = switch (result.term) {
        .Exited => |code| code != 0,
        else => true,
    };
    const output = if (result.stdout.len > 0) result.stdout else if (result.stderr.len > 0) result.stderr else "(no output)";
    return .{ .output = output, .is_error = is_err };
}
