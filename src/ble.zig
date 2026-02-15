const std = @import("std");
const transport = @import("transport.zig");

/// BLE GATT Transport for YoctoClaw.
///
/// Protocol:
///   Service UUID:        0xPC01 (custom)
///   TX Characteristic:   0xPC02 (device → host, NOTIFY)
///   RX Characteristic:   0xPC03 (host → device, WRITE)
///   MTU: 247 bytes (BLE 5.x), payload: 244 bytes
///
/// On real hardware (nRF5340, nRF52840):
///   This module links against the Nordic SoftDevice via @cImport.
///   Build with: zig build -Dble=true -Dtarget=thumb-none-eabi
///
/// On desktop (testing):
///   Uses a Unix domain socket to simulate BLE, connecting
///   to the bridge.py script which acts as the BLE central.
///
/// Architecture:
///   Ring (peripheral) ←── BLE ──→ Phone (central) ←── HTTPS ──→ Claude API
///                                     ↕
///                                 Tool execution

pub const SERVICE_UUID: u16 = 0xC01;
pub const TX_CHAR_UUID: u16 = 0xC02;
pub const RX_CHAR_UUID: u16 = 0xC03;

pub const BleTransport = struct {
    allocator: std.mem.Allocator,
    // On desktop: Unix socket for simulation
    socket: ?std.posix.socket_t = null,
    // Response buffer
    rx_buf: [4096]u8 = undefined,
    rx_len: usize = 0,
    connected: bool = false,
    // TODO: Implement chunk reassembly for multi-packet responses.
    // Currently, only single-frame responses are supported. For large
    // API responses over real BLE (>244 byte MTU), the bridge should
    // reassemble chunks before sending over the socket.

    pub fn init(allocator: std.mem.Allocator) BleTransport {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BleTransport) void {
        if (self.socket) |s| {
            std.posix.close(s);
        }
    }

    /// Connect to BLE bridge (desktop simulation via Unix socket).
    pub fn connectSimulated(self: *BleTransport, path: []const u8) !void {
        const sock = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
        errdefer std.posix.close(sock);

        var addr = std.posix.sockaddr.un{ .family = std.posix.AF.UNIX, .path = undefined };
        @memset(&addr.path, 0);
        const copy_len = @min(path.len, addr.path.len - 1);
        @memcpy(addr.path[0..copy_len], path[0..copy_len]);

        try std.posix.connect(sock, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        self.socket = sock;
        self.connected = true;
    }

    /// Send data and receive response (request-response pattern).
    fn send(ptr: *anyopaque, data: []const u8) anyerror![]const u8 {
        const self: *BleTransport = @ptrCast(@alignCast(ptr));

        // Chunk if needed
        if (data.len > transport.RPC_MTU) {
            const chunks = try transport.chunkMessage(self.allocator, data);
            for (chunks) |chunk| {
                try self.writeRaw(chunk);
            }
        } else {
            try self.writeRaw(data);
        }

        // Read response (may be chunked)
        return self.readMessage();
    }

    fn writeImpl(ptr: *anyopaque, data: []const u8) anyerror!void {
        const self: *BleTransport = @ptrCast(@alignCast(ptr));
        try self.writeRaw(data);
    }

    fn readImpl(ptr: *anyopaque, buf: []u8) anyerror!usize {
        const self: *BleTransport = @ptrCast(@alignCast(ptr));
        const sock = self.socket orelse return error.NotConnected;
        return std.posix.read(sock, buf);
    }

    fn closeImpl(ptr: *anyopaque) void {
        const self: *BleTransport = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn writeRaw(self: *BleTransport, data: []const u8) !void {
        const sock = self.socket orelse return error.NotConnected;
        // Length-prefixed write: 2 bytes big-endian length + payload
        var len_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &len_buf, @intCast(data.len), .big);
        _ = try std.posix.write(sock, &len_buf);
        _ = try std.posix.write(sock, data);
    }

    fn readMessage(self: *BleTransport) ![]const u8 {
        const sock = self.socket orelse return error.NotConnected;
        // Length-prefixed read
        var len_buf: [2]u8 = undefined;
        const len_read = try std.posix.read(sock, &len_buf);
        if (len_read < 2) return error.ConnectionClosed;

        const msg_len = std.mem.readInt(u16, &len_buf, .big);
        if (msg_len > self.rx_buf.len) return error.MessageTooLarge;

        var total: usize = 0;
        while (total < msg_len) {
            const n = try std.posix.read(sock, self.rx_buf[total..msg_len]);
            if (n == 0) return error.ConnectionClosed;
            total += n;
        }

        return try self.allocator.dupe(u8, self.rx_buf[0..msg_len]);
    }

    pub fn asTransport(self: *BleTransport) transport.Transport {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .send = send,
                .write = writeImpl,
                .read = readImpl,
                .close = closeImpl,
            },
        };
    }
};

// ============================================================
// For real nRF5340 hardware, uncomment and link Nordic SDK:
//
// const nrf = @cImport({
//     @cInclude("ble.h");
//     @cInclude("ble_gatts.h");
// });
//
// pub fn initHardwareBle() !void {
//     nrf.sd_ble_enable(...);
//     // Register GATT service
//     // Set up characteristics
//     // Start advertising
// }
// ============================================================
