const std = @import("std");

/// Fixed-size arena allocator for embedded targets.
///
/// On a smart ring or microcontroller, we can't call mmap/sbrk.
/// This allocator uses a statically-sized buffer and supports
/// reset between agent turns (no per-allocation free).
///
/// Memory layout for a typical embedded YoctoClaw:
///   Total: 32KB arena
///   - Message buffer:    ~8KB (conversation history)
///   - JSON parse buffer: ~8KB (API response parsing)
///   - Tool I/O buffer:   ~8KB (tool call/result data)
///   - Scratch:           ~8KB (temporary allocations)
///
/// Usage:
///   var arena_buf: [32768]u8 = undefined;
///   var arena = FixedArena.init(&arena_buf);
///   const allocator = arena.allocator();
///   // ... use allocator ...
///   arena.reset(); // free everything at once (between turns)

pub fn FixedArena(comptime size: usize) type {
    return struct {
        buffer: [size]u8 = undefined,
        offset: usize = 0,
        peak: usize = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn initWithBuffer(buf: *[size]u8) Self {
            return .{ .buffer = buf.* };
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const alignment = @as(usize, 1) << @intCast(ptr_align);
            const aligned_offset = std.mem.alignForward(usize, self.offset, alignment);

            // Check for overflow: ensure len doesn't overflow when added to aligned_offset
            // and that the result fits within the buffer size
            if (len > size or aligned_offset > size - len) return null;

            const result = self.buffer[aligned_offset..][0..len];
            self.offset = aligned_offset + len;
            self.peak = @max(self.peak, self.offset);
            return result.ptr;
        }

        fn resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
            // Arena doesn't support resize
            return false;
        }

        fn free(_: *anyopaque, _: []u8, _: u8, _: usize) void {
            // Arena doesn't free individual allocations
        }

        /// Reset the arena, freeing all allocations at once.
        /// Call this between agent turns.
        pub fn reset(self: *Self) void {
            self.offset = 0;
        }

        /// How many bytes are currently allocated.
        pub fn used(self: *const Self) usize {
            return self.offset;
        }

        /// How many bytes are available.
        pub fn available(self: *const Self) usize {
            return size - self.offset;
        }

        /// Peak usage (high-water mark).
        pub fn peakUsage(self: *const Self) usize {
            return self.peak;
        }

        /// Usage as a percentage.
        pub fn usagePercent(self: *const Self) u8 {
            return @intCast(@as(u64, self.offset) * 100 / size);
        }
    };
}

// Pre-defined arena sizes for common targets
pub const Arena4K = FixedArena(4096); // Minimal: Colmi R02 class
pub const Arena16K = FixedArena(16384); // Small: nRF52840 budget
pub const Arena32K = FixedArena(32768); // Standard: nRF5340 budget
pub const Arena128K = FixedArena(131072); // Large: Balletto B1 class
pub const Arena256K = FixedArena(262144); // Desktop-embedded hybrid

test "fixed arena basic" {
    var arena = FixedArena(1024).init();
    const alloc = arena.allocator();

    const slice = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), slice.len);
    try std.testing.expect(arena.used() >= 100);

    arena.reset();
    try std.testing.expectEqual(@as(usize, 0), arena.used());
    try std.testing.expect(arena.peakUsage() >= 100);
}

test "fixed arena overflow" {
    var arena = FixedArena(64).init();
    const alloc = arena.allocator();

    const result = alloc.alloc(u8, 128);
    try std.testing.expect(result == error.OutOfMemory);
}

test "arena alignment" {
    var arena = FixedArena(1024).init();
    const alloc = arena.allocator();

    // Allocate 1 byte first to misalign
    _ = try alloc.alloc(u8, 1);
    // Then allocate with 4-byte alignment
    // alloc u32 — requires 4-byte alignment
    const aligned = try alloc.alloc(u32, 1);
    const addr = @intFromPtr(aligned.ptr);
    try std.testing.expectEqual(@as(usize, 0), addr % @alignOf(u32));
}

test "arena peak tracking" {
    var arena = FixedArena(1024).init();
    const alloc = arena.allocator();

    _ = try alloc.alloc(u8, 500);
    try std.testing.expect(arena.peakUsage() >= 500);

    arena.reset();
    try std.testing.expectEqual(@as(usize, 0), arena.used());

    _ = try alloc.alloc(u8, 100);
    // Peak should still reflect the larger allocation
    try std.testing.expect(arena.peakUsage() >= 500);
}

test "arena multiple allocations" {
    var arena = FixedArena(4096).init();
    const alloc = arena.allocator();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try alloc.alloc(u8, 32);
    }
    // 10 * 32 = 320 bytes minimum
    try std.testing.expect(arena.used() >= 320);
    try std.testing.expect(arena.usagePercent() < 50);
}

test "Arena preset sizes" {
    // Verify presets can allocate up to their stated capacity
    var a4k = Arena4K.init();
    const alloc4k = a4k.allocator();
    _ = try alloc4k.alloc(u8, 4000);
    try std.testing.expect(a4k.available() < 100);
}
