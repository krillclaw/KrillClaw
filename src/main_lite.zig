//! KrillClaw Lite entry point — freestanding/embedded.
//! No std.process, no std.fs, no std.http, no GPA.
const std = @import("std");
const build_options = @import("build_options");
const types = @import("types.zig");
const json = @import("json.zig");
const arena_mod = @import("arena.zig");
const config_lite = @import("config_lite.zig");
const tools_lite = @import("tools_lite.zig");
const transport = @import("transport.zig");
const context_mod = @import("context.zig");
const stream_mod = @import("stream.zig");

const VERSION = "0.1.0-lite";

/// 32KB fixed arena for embedded operation
const Arena32K = arena_mod.FixedArena(32 * 1024);

pub fn main() !void {
    var arena = Arena32K.init();
    const allocator = arena.allocator();

    const config = config_lite.load();
    _ = config;
    _ = allocator;

    // In a real embedded deployment, this would:
    // 1. Initialize BLE/UART transport
    // 2. Wait for RPC commands from hub
    // 3. Execute local tools and relay API calls
    // 4. Run the agent loop with RPC-based API adapter
    //
    // For now, this is a compilable skeleton that proves
    // the Lite profile excludes all heavy dependencies.
}
