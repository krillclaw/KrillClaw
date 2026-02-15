const std = @import("std");
const transport = @import("transport.zig");

/// Serial/UART Transport for YoctoClaw.
///
/// Connects to a host machine via serial port (USB-UART, FTDI, etc.).
/// The host runs a bridge script that relays to Claude API and executes tools.
///
/// Protocol: Length-prefixed JSON lines.
///   [2 bytes big-endian length][JSON payload]
///
/// Typical use: ESP32 dev board, Raspberry Pi Pico, or any device
/// with a UART connected to a computer.
///
/// Baud rates: 115200 (default), 230400, 460800, 921600

pub const SerialTransport = struct {
    allocator: std.mem.Allocator,
    fd: ?std.posix.fd_t = null,
    rx_buf: [4096]u8 = undefined,
    connected: bool = false,

    pub fn init(allocator: std.mem.Allocator) SerialTransport {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SerialTransport) void {
        if (self.fd) |f| {
            std.posix.close(f);
        }
    }

    /// Open a serial port.
    pub fn connect(self: *SerialTransport, port: []const u8, baud: u32) !void {
        // Null-terminate the path for posix.open
        const port_z = try self.allocator.dupeZ(u8, port);
        defer self.allocator.free(port_z);

        const fd = try std.posix.open(
            port_z,
            .{ .ACCMODE = .RDWR, .NOCTTY = true },
            0,
        );
        errdefer std.posix.close(fd);

        // Configure serial port
        try configureBaud(fd, baud);

        self.fd = fd;
        self.connected = true;
    }

    fn sendImpl(ptr: *anyopaque, data: []const u8) anyerror![]const u8 {
        const self: *SerialTransport = @ptrCast(@alignCast(ptr));
        try self.writeFrame(data);
        return self.readFrame();
    }

    fn writeImpl(ptr: *anyopaque, data: []const u8) anyerror!void {
        const self: *SerialTransport = @ptrCast(@alignCast(ptr));
        try self.writeFrame(data);
    }

    fn readImpl(ptr: *anyopaque, buf: []u8) anyerror!usize {
        const self: *SerialTransport = @ptrCast(@alignCast(ptr));
        const fd = self.fd orelse return error.NotConnected;
        return std.posix.read(fd, buf);
    }

    fn closeImpl(ptr: *anyopaque) void {
        const self: *SerialTransport = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn writeFrame(self: *SerialTransport, data: []const u8) !void {
        const fd = self.fd orelse return error.NotConnected;
        var len_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &len_buf, @intCast(data.len), .big);
        _ = try std.posix.write(fd, &len_buf);
        _ = try std.posix.write(fd, data);
    }

    fn readFrame(self: *SerialTransport) ![]const u8 {
        const fd = self.fd orelse return error.NotConnected;
        var len_buf: [2]u8 = undefined;

        // Read length prefix
        var len_read: usize = 0;
        while (len_read < 2) {
            const n = try std.posix.read(fd, len_buf[len_read..]);
            if (n == 0) return error.ConnectionClosed;
            len_read += n;
        }

        const msg_len = std.mem.readInt(u16, &len_buf, .big);
        if (msg_len > self.rx_buf.len) return error.MessageTooLarge;

        var total: usize = 0;
        while (total < msg_len) {
            const n = try std.posix.read(fd, self.rx_buf[total..msg_len]);
            if (n == 0) return error.ConnectionClosed;
            total += n;
        }

        return try self.allocator.dupe(u8, self.rx_buf[0..msg_len]);
    }

    pub fn asTransport(self: *SerialTransport) transport.Transport {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .send = sendImpl,
                .write = writeImpl,
                .read = readImpl,
                .close = closeImpl,
            },
        };
    }
};

/// Configure baud rate on a serial port file descriptor.
///
/// Uses stty for baud configuration (Linux/macOS only). This is a pragmatic
/// choice for dev board use — stty is available on all Unix systems where
/// you'd plug in a USB-UART adapter. Errors are non-fatal (serial port
/// may already be configured, or stty may not be available).
///
/// TODO: Replace with termios ioctl for true portability and embedded hosts.
fn configureBaud(fd: std.posix.fd_t, baud: u32) !void {
    const baud_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{baud}) catch return;
    defer std.heap.page_allocator.free(baud_str);

    const fd_str = std.fmt.allocPrint(std.heap.page_allocator, "/dev/fd/{d}", .{fd}) catch return;
    defer std.heap.page_allocator.free(fd_str);

    _ = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "stty", "-F", fd_str, baud_str, "raw", "-echo" },
    }) catch {};
}
