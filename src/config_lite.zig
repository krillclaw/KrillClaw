//! Lite profile configuration — hardcoded defaults, no filesystem or env vars.
const types = @import("types.zig");

pub const LiteConfig = struct {
    system_prompt: []const u8 =
        \\You are KrillClaw Lite, a minimal embedded agent. You operate over BLE/Serial.
        \\Available tools: gpio_read, sensor_read, device_info.
    ,
    max_turns: u32 = 10,
    transport: types.TransportKind = .ble,
    ble_device: ?[]const u8 = null,
    serial_port: ?[]const u8 = null,
    serial_baud: u32 = 115200,
};

pub fn load() LiteConfig {
    return .{};
}
