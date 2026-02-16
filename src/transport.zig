const std = @import("std");
const build_options = @import("build_options");
const types = @import("types.zig");

/// Abstract transport interface.
///
/// YoctoClaw can run over different physical layers:
/// - HTTP (desktop: direct TLS to Claude API)
/// - BLE  (embedded: GATT service, phone bridges to API)
/// - Serial (dev boards: UART to host, host bridges to API)
///
/// For BLE and Serial, the agent runs on the device but sends
/// tool calls and API requests to a host/phone that executes them.
/// The protocol is simple JSON-line messages.
pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Send a request and receive a response (blocking).
        send: *const fn (ptr: *anyopaque, data: []const u8) anyerror![]const u8,
        /// Send raw bytes without expecting a response.
        write: *const fn (ptr: *anyopaque, data: []const u8) anyerror!void,
        /// Read raw bytes (blocking until data available).
        read: *const fn (ptr: *anyopaque, buf: []u8) anyerror!usize,
        /// Close the transport.
        close: *const fn (ptr: *anyopaque) void,
    };

    pub fn send(self: Transport, data: []const u8) ![]const u8 {
        return self.vtable.send(self.ptr, data);
    }

    pub fn write(self: Transport, data: []const u8) !void {
        return self.vtable.write(self.ptr, data);
    }

    pub fn read(self: Transport, buf: []u8) !usize {
        return self.vtable.read(self.ptr, buf);
    }

    pub fn close(self: Transport) void {
        self.vtable.close(self.ptr);
    }
};

// ============================================================
// RPC Protocol for BLE/Serial transports
// ============================================================
//
// When running on embedded hardware, YoctoClaw can't make HTTP
// requests or execute bash commands directly. Instead, it sends
// JSON-line messages over the transport to a host that does it.
//
// Request types:
//   {"type":"api","provider":"claude","body":"<json>"}
//   {"type":"tool","name":"bash","input":"<json>"}
//
// Response:
//   {"type":"api_result","body":"<json>"}
//   {"type":"tool_result","output":"<text>","is_error":false}
//
// Chunking: Messages >MTU are split with a header:
//   [chunk_index, total_chunks, ...payload...]
// Default MTU: 244 bytes (BLE 5.x with 247 byte ATT MTU - 3 byte header)

pub const RPC_MTU = 244;

pub const RpcRequest = struct {
    type: []const u8,
    // For api requests
    provider: ?[]const u8 = null,
    body: ?[]const u8 = null,
    // For tool requests
    name: ?[]const u8 = null,
    input: ?[]const u8 = null,
};

/// Build an RPC message for an API call.
/// Provider name is escaped; body is raw JSON (passed through as-is).
pub fn buildApiRpc(allocator: std.mem.Allocator, provider: []const u8, body: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer();
    try w.writeAll("{\"type\":\"api\",\"provider\":\"");
    // Provider is a controlled enum string (claude/openai/ollama) but we
    // escape anyway for correctness if custom providers are added later.
    for (provider) |c| {
        if (c == '"') try w.writeAll("\\\"") else if (c == '\\') try w.writeAll("\\\\") else try w.writeByte(c);
    }
    try w.writeAll("\",\"body\":");
    try w.writeAll(body); // body is already valid JSON
    try w.writeByte('}');
    return buf.toOwnedSlice(allocator);
}

/// Build an RPC message for a tool call.
/// Tool name is escaped; input is raw JSON (passed through as-is).
pub fn buildToolRpc(allocator: std.mem.Allocator, name: []const u8, input: []const u8) ![]const u8 {
    var buf: std.ArrayList(u8) = .{};
    const w = buf.writer();
    try w.writeAll("{\"type\":\"tool\",\"name\":\"");
    for (name) |c| {
        if (c == '"') try w.writeAll("\\\"") else if (c == '\\') try w.writeAll("\\\\") else try w.writeByte(c);
    }
    try w.writeAll("\",\"input\":");
    try w.writeAll(input); // input is already valid JSON
    try w.writeByte('}');
    return buf.toOwnedSlice(allocator);
}

/// Chunk a message for BLE transport.
pub fn chunkMessage(allocator: std.mem.Allocator, data: []const u8) ![]const []const u8 {
    const payload_size = RPC_MTU - 2; // 2 bytes for chunk header
    const num_chunks = (data.len + payload_size - 1) / payload_size;

    var chunks = try allocator.alloc([]const u8, num_chunks);
    for (0..num_chunks) |i| {
        const start = i * payload_size;
        const end = @min(start + payload_size, data.len);
        const payload = data[start..end];

        var chunk = try allocator.alloc(u8, payload.len + 2);
        chunk[0] = @intCast(i);
        chunk[1] = @intCast(num_chunks);
        @memcpy(chunk[2..], payload);
        chunks[i] = chunk;
    }
    return chunks;
}
