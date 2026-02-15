//! Tool dispatcher — selects profile at comptime via build_options.
const std = @import("std");
const types = @import("types.zig");
const build_options = @import("build_options");

const profile_mod = switch (build_options.profile) {
    .coding => @import("tools_coding.zig"),
    .iot => @import("tools_iot.zig"),
    .robotics => @import("tools_robotics.zig"),
};

pub const ToolResult = profile_mod.ToolResult;
pub const tool_definitions = profile_mod.tool_definitions;

/// Execute a tool call — delegates to the active profile.
pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    return profile_mod.execute(allocator, tool);
}

// Re-export matchGlob for tests (only available in coding profile)
pub const matchGlob = if (build_options.profile == .coding) @import("tools_coding.zig").matchGlob else struct {
    fn f(_: []const u8, _: []const u8) bool { return false; }
}.f;

// ============================================================
// Tests (these test the coding profile by default)
// ============================================================

test "execute unknown tool" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{ .id = "t1", .name = "nonexistent", .input_raw = "{}" });
    try std.testing.expect(result.is_error);
    try std.testing.expectEqualStrings("Unknown tool", result.output);
}

test "bash echo" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "bash",
        .input_raw = "{\"command\":\"echo hello\"}",
    });
    try std.testing.expect(!result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "hello") != null);
}

test "bash exit code" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "bash",
        .input_raw = "{\"command\":\"false\"}",
    });
    try std.testing.expect(result.is_error);
}

test "read_file" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_read.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("test content 123");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "read_file", .input_raw = input });
    try std.testing.expect(!result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "test content 123") != null);
}

test "write_file" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_write.txt";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\",\"content\":\"written data\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "write_file", .input_raw = input });
    try std.testing.expect(!result.is_error);
    const f = try std.fs.cwd().openFile(tmp_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, 1024);
    defer alloc.free(content);
    try std.testing.expectEqualStrings("written data", content);
}

test "edit_file unique match" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("hello world");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\",\"old_string\":\"hello\",\"new_string\":\"goodbye\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(!result.is_error);
    const f = try std.fs.cwd().openFile(tmp_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, 1024);
    defer alloc.free(content);
    try std.testing.expectEqualStrings("goodbye world", content);
}

test "edit_file no match" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit_nomatch.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("hello world");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\",\"old_string\":\"NOTFOUND\",\"new_string\":\"x\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "not found") != null);
}

test "edit_file multiple matches" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit_multi.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("foo bar foo");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};
    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\",\"old_string\":\"foo\",\"new_string\":\"baz\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "must be unique") != null);
}

test "search no injection" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "search",
        .input_raw = "{\"pattern\":\"'; rm -rf /\",\"path\":\"/tmp\"}",
    });
    try std.testing.expect(!result.is_error or
        std.mem.indexOf(u8, result.output, "No matches") != null or
        std.mem.indexOf(u8, result.output, "Search failed") != null);
}

test "list_files no injection" {
    if (build_options.profile != .coding) return;
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "list_files",
        .input_raw = "{\"path\":\"/tmp\",\"pattern\":\"'; rm -rf /\"}",
    });
    try std.testing.expect(!result.is_error or
        std.mem.indexOf(u8, result.output, "no files") != null);
}

test "matchGlob" {
    if (build_options.profile != .coding) return;
    try std.testing.expect(matchGlob("main.zig", "*.zig"));
    try std.testing.expect(!matchGlob("main.go", "*.zig"));
    try std.testing.expect(matchGlob("main.zig", "*"));
    try std.testing.expect(matchGlob("src_test.zig", "src*"));
    try std.testing.expect(matchGlob("main.zig", "main.zig"));
    try std.testing.expect(!matchGlob("other.zig", "main.zig"));
}
