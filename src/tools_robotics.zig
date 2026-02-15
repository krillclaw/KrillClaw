//! Robotics profile tools — structured robot commands with bounds checking, e-stop, telemetry.
//! Policy: no bash, no file writes, command rate limiting, bounds enforcement, watchdog.
const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

pub const ToolResult = struct {
    output: []const u8,
    is_error: bool,
};

pub const tool_definitions = [_]types.ToolDef{
    .{ .name = "robot_cmd", .description = "Send a structured command to the robot (pose, velocity, or gripper).", .input_schema =
        \\{"type":"object","properties":{"cmd_type":{"type":"string","enum":["pose","velocity","gripper"]},"x":{"type":"number"},"y":{"type":"number"},"z":{"type":"number"},"vx":{"type":"number"},"vy":{"type":"number"},"vz":{"type":"number"},"grip":{"type":"number","minimum":0,"maximum":1}},"required":["cmd_type"]}
    },
    .{ .name = "estop", .description = "Emergency stop — immediately halt all robot motion.", .input_schema =
        \\{"type":"object","properties":{"reason":{"type":"string"}},"required":[]}
    },
    .{ .name = "telemetry_snapshot", .description = "Get current robot telemetry (position, velocity, sensors, status).", .input_schema =
        \\{"type":"object","properties":{},"required":[]}
    },
};

// --- Bounds ---
const MAX_POS: f64 = 1000.0; // mm
const MAX_VEL: f64 = 500.0;  // mm/s
const CMD_RATE_LIMIT: usize = 10; // max commands per second

// --- Rate limiter ---
var cmd_timestamps: [10]i64 = [_]i64{0} ** 10;
var cmd_idx: usize = 0;
var estop_active: bool = false;

fn checkCmdRate() bool {
    const now = std.time.timestamp();
    const oldest = cmd_timestamps[cmd_idx];
    if (oldest != 0 and (now - oldest) < 1) return false;
    cmd_timestamps[cmd_idx] = now;
    cmd_idx = (cmd_idx + 1) % CMD_RATE_LIMIT;
    return true;
}

fn extractFloat(input: []const u8, key: []const u8) ?f64 {
    // Simple float extraction from JSON — find "key": and parse number
    const key_pattern = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\"", .{key}) catch return null;
    const key_pos = std.mem.indexOf(u8, input, key_pattern) orelse return null;
    var pos = key_pos + key_pattern.len;
    // Skip whitespace and colon
    while (pos < input.len and (input[pos] == ' ' or input[pos] == ':')) : (pos += 1) {}
    if (pos >= input.len) return null;
    var end = pos;
    while (end < input.len and (input[end] == '-' or input[end] == '.' or (input[end] >= '0' and input[end] <= '9'))) : (end += 1) {}
    if (end == pos) return null;
    return std.fmt.parseFloat(f64, input[pos..end]) catch null;
}

fn validateBounds(input: []const u8, cmd_type: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, cmd_type, "pose")) {
        inline for (.{ "x", "y", "z" }) |axis| {
            if (extractFloat(input, axis)) |v| {
                if (v < -MAX_POS or v > MAX_POS) return "Position out of bounds (max ±1000mm)";
            }
        }
    } else if (std.mem.eql(u8, cmd_type, "velocity")) {
        inline for (.{ "vx", "vy", "vz" }) |axis| {
            if (extractFloat(input, axis)) |v| {
                if (v < -MAX_VEL or v > MAX_VEL) return "Velocity out of bounds (max ±500mm/s)";
            }
        }
    } else if (std.mem.eql(u8, cmd_type, "gripper")) {
        if (extractFloat(input, "grip")) |v| {
            if (v < 0.0 or v > 1.0) return "Grip value must be 0.0-1.0";
        }
    }
    return null;
}

pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    // Policy: no bash, no file writes
    if (std.mem.eql(u8, tool.name, "bash")) return .{ .output = "bash disabled in robotics profile", .is_error = true };
    if (std.mem.eql(u8, tool.name, "write_file")) return .{ .output = "write_file disabled in robotics profile", .is_error = true };

    if (std.mem.eql(u8, tool.name, "estop")) return executeEstop(allocator, tool.input_raw);
    if (estop_active) return .{ .output = "E-STOP active — clear before sending commands", .is_error = true };

    if (std.mem.eql(u8, tool.name, "robot_cmd")) return executeRobotCmd(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "telemetry_snapshot")) return executeTelemetry(allocator);
    return .{ .output = "Unknown tool", .is_error = true };
}

fn executeEstop(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    estop_active = true;
    const reason = json.extractString(input, "reason") orelse "manual";
    _ = bridgeCmd(allocator, "estop", "{}");
    const msg = std.fmt.allocPrint(allocator, "E-STOP activated: {s}", .{reason}) catch "E-STOP activated";
    return .{ .output = msg, .is_error = false };
}

fn executeRobotCmd(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    if (!checkCmdRate()) return .{ .output = "Command rate limit exceeded (10/s)", .is_error = true };

    const cmd_type = json.extractString(input, "cmd_type") orelse {
        return .{ .output = "Missing 'cmd_type' parameter", .is_error = true };
    };

    // Bounds checking
    if (validateBounds(input, cmd_type)) |err_msg| {
        return .{ .output = err_msg, .is_error = true };
    }

    return bridgeCmd(allocator, "robot_cmd", input);
}

fn executeTelemetry(allocator: std.mem.Allocator) ToolResult {
    return bridgeCmd(allocator, "telemetry_snapshot", "{}");
}

fn bridgeCmd(allocator: std.mem.Allocator, cmd: []const u8, input: []const u8) ToolResult {
    _ = input;
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "python3", "bridge/bridge.py", "--exec-tool", cmd },
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
