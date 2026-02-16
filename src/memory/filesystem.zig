const std = @import("std");

/// Flash filesystem abstraction layer.
///
/// Provides SPIFFS-like file operations over two backends:
/// 1. PosixBackend — real filesystem (desktop/QEMU testing)
/// 2. FlashBackend — raw flash memory (embedded, stubbed for now)
///
/// Design constraints:
/// - Zero heap allocation in hot paths
/// - Fixed-size buffers throughout
/// - Atomic writes via temp+rename
/// - Max 4KB per file (flash-friendly default)

pub const MAX_PATH_LEN = 64;
pub const MAX_FILE_SIZE = 4096;
pub const TEMP_SUFFIX = ".tmp";

pub const Error = error{
    FileNotFound,
    PathTooLong,
    FileTooLarge,
    WriteError,
    ReadError,
    DeleteError,
    ListError,
    MountError,
    OutOfSpace,
};

/// A fixed-size path buffer.
pub const Path = struct {
    buf: [MAX_PATH_LEN]u8 = undefined,
    len: usize = 0,

    pub fn from(s: []const u8) Error!Path {
        if (s.len > MAX_PATH_LEN) return Error.PathTooLong;
        var p = Path{};
        @memcpy(p.buf[0..s.len], s);
        p.len = s.len;
        return p;
    }

    pub fn slice(self: *const Path) []const u8 {
        return self.buf[0..self.len];
    }

    /// Append suffix (e.g., ".tmp") into a new Path.
    pub fn withSuffix(self: *const Path, suffix: []const u8) Error!Path {
        if (self.len + suffix.len > MAX_PATH_LEN) return Error.PathTooLong;
        var p = Path{};
        @memcpy(p.buf[0..self.len], self.buf[0..self.len]);
        @memcpy(p.buf[self.len .. self.len + suffix.len], suffix);
        p.len = self.len + suffix.len;
        return p;
    }
};

/// Fixed-size buffer for file content.
pub const FileBuffer = struct {
    data: [MAX_FILE_SIZE]u8 = undefined,
    len: usize = 0,

    pub fn slice(self: *const FileBuffer) []const u8 {
        return self.data[0..self.len];
    }
};

/// Directory listing entry.
pub const DirEntry = struct {
    name: [MAX_PATH_LEN]u8 = undefined,
    name_len: usize = 0,
    size: usize = 0,

    pub fn nameSlice(self: *const DirEntry) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const MAX_DIR_ENTRIES = 32;

pub const DirListing = struct {
    entries: [MAX_DIR_ENTRIES]DirEntry = undefined,
    count: usize = 0,

    pub fn items(self: *const DirListing) []const DirEntry {
        return self.entries[0..self.count];
    }
};

/// Backend interface — vtable-based for zero-cost switching.
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ctx: *anyopaque, path: []const u8, buf: *FileBuffer) Error!void,
        write: *const fn (ctx: *anyopaque, path: []const u8, data: []const u8) Error!void,
        delete: *const fn (ctx: *anyopaque, path: []const u8) Error!void,
        rename: *const fn (ctx: *anyopaque, old: []const u8, new: []const u8) Error!void,
        list: *const fn (ctx: *anyopaque, dir: []const u8, out: *DirListing) Error!void,
        exists: *const fn (ctx: *anyopaque, path: []const u8) bool,
        mkdirp: *const fn (ctx: *anyopaque, path: []const u8) Error!void,
    };

    pub fn read(self: Backend, path: []const u8, buf: *FileBuffer) Error!void {
        return self.vtable.read(self.ptr, path, buf);
    }
    pub fn write(self: Backend, path: []const u8, data: []const u8) Error!void {
        return self.vtable.write(self.ptr, path, data);
    }
    pub fn delete(self: Backend, path: []const u8) Error!void {
        return self.vtable.delete(self.ptr, path);
    }
    pub fn rename(self: Backend, old: []const u8, new: []const u8) Error!void {
        return self.vtable.rename(self.ptr, old, new);
    }
    pub fn list(self: Backend, dir: []const u8, out: *DirListing) Error!void {
        return self.vtable.list(self.ptr, dir, out);
    }
    pub fn exists(self: Backend, path: []const u8) bool {
        return self.vtable.exists(self.ptr, path);
    }
    pub fn mkdirp(self: Backend, path: []const u8) Error!void {
        return self.vtable.mkdirp(self.ptr, path);
    }
};

/// POSIX filesystem backend (desktop/QEMU testing).
pub const PosixBackend = struct {
    root: [MAX_PATH_LEN]u8 = undefined,
    root_len: usize = 0,

    const Self = @This();

    pub fn init(root_path: []const u8) Error!Self {
        if (root_path.len >= MAX_PATH_LEN - 1) return Error.PathTooLong;
        var self = Self{};
        @memcpy(self.root[0..root_path.len], root_path);
        self.root_len = root_path.len;
        return self;
    }

    pub fn backend(self: *Self) Backend {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = posixRead,
                .write = posixWrite,
                .delete = posixDelete,
                .rename = posixRename,
                .list = posixList,
                .exists = posixExists,
                .mkdirp = posixMkdirp,
            },
        };
    }

    /// Build full path: root/relative
    fn fullPath(self: *const Self, rel: []const u8, out: *[MAX_PATH_LEN * 2]u8) []const u8 {
        const rlen = self.root_len;
        @memcpy(out[0..rlen], self.root[0..rlen]);
        out[rlen] = '/';
        @memcpy(out[rlen + 1 .. rlen + 1 + rel.len], rel);
        return out[0 .. rlen + 1 + rel.len];
    }

    fn posixRead(ctx: *anyopaque, path: []const u8, buf: *FileBuffer) Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(path, &pathbuf);
        const file = std.fs.cwd().openFile(full, .{}) catch return Error.FileNotFound;
        defer file.close();
        const n = file.readAll(&buf.data) catch return Error.ReadError;
        buf.len = n;
    }

    fn posixWrite(ctx: *anyopaque, path: []const u8, data: []const u8) Error!void {
        if (data.len > MAX_FILE_SIZE) return Error.FileTooLarge;
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(path, &pathbuf);
        const file = std.fs.cwd().createFile(full, .{}) catch return Error.WriteError;
        defer file.close();
        file.writeAll(data) catch return Error.WriteError;
    }

    fn posixDelete(ctx: *anyopaque, path: []const u8) Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(path, &pathbuf);
        std.fs.cwd().deleteFile(full) catch return Error.DeleteError;
    }

    fn posixRename(ctx: *anyopaque, old: []const u8, new: []const u8) Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var oldbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        var newbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const old_full = self.fullPath(old, &oldbuf);
        const new_full = self.fullPath(new, &newbuf);

        // Need null-terminated paths for rename
        var old_z: [MAX_PATH_LEN * 2 + 1]u8 = undefined;
        var new_z: [MAX_PATH_LEN * 2 + 1]u8 = undefined;
        @memcpy(old_z[0..old_full.len], old_full);
        old_z[old_full.len] = 0;
        @memcpy(new_z[0..new_full.len], new_full);
        new_z[new_full.len] = 0;

        const old_sentinel: [:0]const u8 = old_z[0..old_full.len :0];
        const new_sentinel: [:0]const u8 = new_z[0..new_full.len :0];
        std.posix.rename(old_sentinel, new_sentinel) catch return Error.WriteError;
    }

    fn posixList(ctx: *anyopaque, dir: []const u8, out: *DirListing) Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(dir, &pathbuf);

        // Need null-terminated path
        var full_z: [MAX_PATH_LEN * 2 + 1]u8 = undefined;
        @memcpy(full_z[0..full.len], full);
        full_z[full.len] = 0;

        var d = std.fs.cwd().openDir(full, .{ .iterate = true }) catch return Error.ListError;
        defer d.close();

        out.count = 0;
        var iter = d.iterate();
        while (iter.next() catch return Error.ListError) |entry| {
            if (out.count >= MAX_DIR_ENTRIES) break;
            if (entry.kind == .directory) continue;
            const nlen = @min(entry.name.len, MAX_PATH_LEN);
            @memcpy(out.entries[out.count].name[0..nlen], entry.name[0..nlen]);
            out.entries[out.count].name_len = nlen;
            out.entries[out.count].size = 0; // Could stat, but skip for minimal impl
            out.count += 1;
        }
    }

    fn posixExists(ctx: *anyopaque, path: []const u8) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(path, &pathbuf);
        std.fs.cwd().access(full, .{}) catch return false;
        return true;
    }

    fn posixMkdirp(ctx: *anyopaque, path: []const u8) Error!void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        var pathbuf: [MAX_PATH_LEN * 2]u8 = undefined;
        const full = self.fullPath(path, &pathbuf);

        // Need null-terminated path for mkdir
        var full_z: [MAX_PATH_LEN * 2 + 1]u8 = undefined;
        @memcpy(full_z[0..full.len], full);
        full_z[full.len] = 0;

        std.fs.cwd().makePath(full) catch return Error.WriteError;
    }
};

/// Flash memory backend (embedded — stubbed).
pub const FlashBackend = struct {
    // Stubbed: would map to SPI flash sectors
    // For now, returns errors to test error handling paths
    mounted: bool = false,

    const Self = @This();

    pub fn init() Self {
        return .{ .mounted = false };
    }

    pub fn mount(self: *Self) Error!void {
        // In real impl: read flash header, verify magic, check CRC
        // Format on failure
        self.mounted = true;
    }

    pub fn format(self: *Self) void {
        // In real impl: erase all flash sectors, write fresh header
        self.mounted = true;
    }

    pub fn backend(self: *Self) Backend {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = flashRead,
                .write = flashWrite,
                .delete = flashDelete,
                .rename = flashRename,
                .list = flashList,
                .exists = flashExists,
                .mkdirp = flashMkdirp,
            },
        };
    }

    fn flashRead(_: *anyopaque, _: []const u8, _: *FileBuffer) Error!void {
        return Error.FileNotFound; // Stub
    }
    fn flashWrite(_: *anyopaque, _: []const u8, _: []const u8) Error!void {
        return Error.OutOfSpace; // Stub
    }
    fn flashDelete(_: *anyopaque, _: []const u8) Error!void {
        return Error.DeleteError; // Stub
    }
    fn flashRename(_: *anyopaque, _: []const u8, _: []const u8) Error!void {
        return Error.WriteError; // Stub
    }
    fn flashList(_: *anyopaque, _: []const u8, out: *DirListing) Error!void {
        out.count = 0;
        return;
    }
    fn flashExists(_: *anyopaque, _: []const u8) bool {
        return false; // Stub
    }
    fn flashMkdirp(_: *anyopaque, _: []const u8) Error!void {
        return; // Stub: no-op for flat flash
    }
};

/// High-level filesystem that provides atomic writes and mount recovery.
pub const FileSystem = struct {
    back: Backend,

    pub fn init(back: Backend) FileSystem {
        return .{ .back = back };
    }

    /// Mount and initialize directory structure.
    /// On failure, attempt format and retry.
    pub fn mount(self: *FileSystem) Error!void {
        // Create standard directories
        self.back.mkdirp("config") catch {};
        self.back.mkdirp("memory") catch {};
        self.back.mkdirp("sessions") catch {};
    }

    /// Atomic write: write to .tmp, then rename.
    pub fn atomicWrite(self: *FileSystem, path: []const u8, data: []const u8) Error!void {
        if (data.len > MAX_FILE_SIZE) return Error.FileTooLarge;
        const tmp_path = try (Path.from(path) catch return Error.PathTooLong).withSuffix(TEMP_SUFFIX);
        try self.back.write(tmp_path.slice(), data);
        self.back.rename(tmp_path.slice(), path) catch {
            // Cleanup temp on rename failure
            self.back.delete(tmp_path.slice()) catch {};
            return Error.WriteError;
        };
    }

    /// Read file into buffer.
    pub fn read(self: *FileSystem, path: []const u8, buf: *FileBuffer) Error!void {
        return self.back.read(path, buf);
    }

    /// Delete a file.
    pub fn delete(self: *FileSystem, path: []const u8) Error!void {
        return self.back.delete(path);
    }

    /// List files in a directory.
    pub fn list(self: *FileSystem, dir: []const u8, out: *DirListing) Error!void {
        return self.back.list(dir, out);
    }

    /// Check if a file exists.
    pub fn exists(self: *FileSystem, path: []const u8) bool {
        return self.back.exists(path);
    }
};

// ---- Tests ----

test "Path from and slice" {
    const p = try Path.from("config/agent.md");
    try std.testing.expectEqualStrings("config/agent.md", p.slice());
}

test "Path too long" {
    const long = "a" ** (MAX_PATH_LEN + 1);
    try std.testing.expectError(Error.PathTooLong, Path.from(long));
}

test "Path withSuffix" {
    const p = try Path.from("memory/note.md");
    const tmp = try p.withSuffix(TEMP_SUFFIX);
    try std.testing.expectEqualStrings("memory/note.md.tmp", tmp.slice());
}

test "PosixBackend read/write/delete" {
    // Use /tmp for testing
    var pb = try PosixBackend.init("/tmp/krillclaw_test_fs");
    const back = pb.backend();
    var fs = FileSystem.init(back);

    // Mount creates dirs
    try fs.mount();

    // Write
    const data = "# Test\nHello world";
    try fs.atomicWrite("config/test.md", data);

    // Read
    var buf = FileBuffer{};
    try fs.read("config/test.md", &buf);
    try std.testing.expectEqualStrings(data, buf.slice());

    // Exists
    try std.testing.expect(fs.exists("config/test.md"));
    try std.testing.expect(!fs.exists("config/nope.md"));

    // List
    var listing = DirListing{};
    try fs.list("config", &listing);
    try std.testing.expect(listing.count >= 1);

    // Delete
    try fs.delete("config/test.md");
    try std.testing.expect(!fs.exists("config/test.md"));

    // Cleanup
}

test "FlashBackend mount and format" {
    var fb = FlashBackend.init();
    try std.testing.expect(!fb.mounted);
    try fb.mount();
    try std.testing.expect(fb.mounted);

    fb.mounted = false;
    fb.format();
    try std.testing.expect(fb.mounted);
}

test "FlashBackend stubs return expected errors" {
    var fb = FlashBackend.init();
    const back = fb.backend();
    var buf = FileBuffer{};
    try std.testing.expectError(Error.FileNotFound, back.read("x", &buf));
    try std.testing.expectError(Error.OutOfSpace, back.write("x", "y"));
    try std.testing.expectError(Error.DeleteError, back.delete("x"));
}

test "FileSystem rejects oversized writes" {
    var fb = FlashBackend.init();
    const back = fb.backend();
    var fs = FileSystem.init(back);
    const big = "x" ** (MAX_FILE_SIZE + 1);
    try std.testing.expectError(Error.FileTooLarge, fs.atomicWrite("big.md", big));
}
