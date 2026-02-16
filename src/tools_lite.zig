//! Lite profile tools — local-only operations (GPIO, sensors, device info).
//! No process spawning, no filesystem, no HTTP.
const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

pub const ToolResult = struct {
    output: []const u8,
    is_error: bool,
    allocated: bool = false,

    pub fn deinit(self: ToolResult, allocator: std.mem.Allocator) void {
        if (self.allocated) allocator.free(self.output);
    }
};

pub const tool_definitions =
    \\[{"name":"device_info","description":"Get device status and info","input_schema":{"type":"object","properties":{},"required":[]}},
    \\{"name":"gpio_read","description":"Read a GPIO pin value","input_schema":{"type":"object","properties":{"pin":{"type":"integer","description":"GPIO pin number"}},"required":["pin"]}},
    \\{"name":"sensor_read","description":"Read a sensor value","input_schema":{"type":"object","properties":{"sensor":{"type":"string","description":"Sensor name"}},"required":["sensor"]}}]
;

pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    _ = allocator;
    if (std.mem.eql(u8, tool.name, "device_info")) {
        return .{ .output = "{\"profile\":\"lite\",\"transport\":\"ble\",\"status\":\"ok\"}", .is_error = false };
    } else if (std.mem.eql(u8, tool.name, "gpio_read")) {
        return .{ .output = "{\"value\":0}", .is_error = false };
    } else if (std.mem.eql(u8, tool.name, "sensor_read")) {
        return .{ .output = "{\"value\":0.0,\"unit\":\"unknown\"}", .is_error = false };
    }
    return .{ .output = "Unknown tool", .is_error = true };
}
