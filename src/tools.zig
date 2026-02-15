const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

pub const ToolResult = struct {
    output: []const u8,
    is_error: bool,
};

/// Execute a tool call and return the result.
pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    if (std.mem.eql(u8, tool.name, "bash")) return executeBash(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "read_file")) return executeReadFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "write_file")) return executeWriteFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "edit_file")) return executeEditFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "search")) return executeSearch(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "list_files")) return executeListFiles(allocator, tool.input_raw);
    return .{ .output = "Unknown tool", .is_error = true };
}

fn executeBash(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const command = json.extractString(input, "command") orelse {
        return .{ .output = "Missing 'command' parameter", .is_error = true };
    };

    // Unescape the command (it comes from JSON)
    const unescaped_cmd = json.unescape(allocator, command) catch command;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", unescaped_cmd },
        .max_output_bytes = 1024 * 256,
    }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to execute: {}", .{err}) catch "exec error";
        return .{ .output = msg, .is_error = true };
    };

    const is_err = switch (result.term) {
        .Exited => |code| code != 0,
        else => true,
    };

    if (result.stderr.len > 0 and result.stdout.len > 0) {
        const combined = std.fmt.allocPrint(allocator, "{s}\n--- stderr ---\n{s}", .{ result.stdout, result.stderr }) catch result.stdout;
        return .{ .output = combined, .is_error = is_err };
    } else if (result.stderr.len > 0) {
        return .{ .output = result.stderr, .is_error = is_err };
    } else if (result.stdout.len > 0) {
        return .{ .output = result.stdout, .is_error = is_err };
    }
    return .{ .output = "(no output)", .is_error = is_err };
}

fn executeReadFile(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot open '{s}': {}", .{ path, err }) catch "open error";
        return .{ .output = msg, .is_error = true };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot read: {}", .{err}) catch "read error";
        return .{ .output = msg, .is_error = true };
    };

    return .{ .output = if (content.len == 0) "(empty file)" else content, .is_error = false };
}

fn executeWriteFile(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };
    const content = json.extractString(input, "content") orelse {
        return .{ .output = "Missing 'content' parameter", .is_error = true };
    };

    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch {};
    }

    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot create '{s}': {}", .{ path, err }) catch "create error";
        return .{ .output = msg, .is_error = true };
    };
    defer file.close();

    const unescaped = json.unescape(allocator, content) catch content;
    file.writeAll(unescaped) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Write failed: {}", .{err}) catch "write error";
        return .{ .output = msg, .is_error = true };
    };

    const msg = std.fmt.allocPrint(allocator, "Wrote {d} bytes to {s}", .{ unescaped.len, path }) catch "wrote file";
    return .{ .output = msg, .is_error = false };
}

fn executeEditFile(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };
    const old_string_raw = json.extractString(input, "old_string") orelse {
        return .{ .output = "Missing 'old_string' parameter", .is_error = true };
    };
    const new_string_raw = json.extractString(input, "new_string") orelse {
        return .{ .output = "Missing 'new_string' parameter", .is_error = true };
    };

    const old_string = json.unescape(allocator, old_string_raw) catch old_string_raw;
    const new_string = json.unescape(allocator, new_string_raw) catch new_string_raw;

    // Read existing file
    const file_content = blk: {
        const f = std.fs.cwd().openFile(path, .{}) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Cannot open '{s}': {}", .{ path, err }) catch "open error";
            return .{ .output = msg, .is_error = true };
        };
        defer f.close();
        break :blk f.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Cannot read: {}", .{err}) catch "read error";
            return .{ .output = msg, .is_error = true };
        };
    };

    // Find and count occurrences
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, file_content[search_pos..], old_string)) |idx| {
        count += 1;
        search_pos += idx + old_string.len;
    }

    if (count == 0) {
        return .{ .output = "old_string not found in file", .is_error = true };
    }
    if (count > 1) {
        const msg = std.fmt.allocPrint(allocator, "old_string found {d} times (must be unique)", .{count}) catch "multiple matches";
        return .{ .output = msg, .is_error = true };
    }

    // Replace
    const idx = std.mem.indexOf(u8, file_content, old_string).?;
    const new_content = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        file_content[0..idx],
        new_string,
        file_content[idx + old_string.len ..],
    }) catch {
        return .{ .output = "Failed to build replacement", .is_error = true };
    };

    // Write back
    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot write '{s}': {}", .{ path, err }) catch "write error";
        return .{ .output = msg, .is_error = true };
    };
    defer file.close();
    file.writeAll(new_content) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Write failed: {}", .{err}) catch "write error";
        return .{ .output = msg, .is_error = true };
    };

    const msg = std.fmt.allocPrint(allocator, "Edited {s} ({d} bytes changed)", .{
        path, @as(i64, @intCast(new_string.len)) - @as(i64, @intCast(old_string.len)),
    }) catch "edited file";
    return .{ .output = msg, .is_error = false };
}

fn executeSearch(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const pattern = json.extractString(input, "pattern") orelse {
        return .{ .output = "Missing 'pattern' parameter", .is_error = true };
    };
    const search_path = json.extractString(input, "path") orelse ".";

    const unescaped_pattern = json.unescape(allocator, pattern) catch pattern;

    // Pure Zig implementation — no shell, no injection risk
    var results = std.ArrayList(u8).init(allocator);
    var match_count: usize = 0;
    const max_matches: usize = 100;

    // Check if search_path is a file or directory
    const stat = std.fs.cwd().statFile(search_path) catch {
        // Try as directory
        searchDir(allocator, search_path, unescaped_pattern, &results, &match_count, max_matches, 0) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Search failed: {}", .{err}) catch "search error";
            return .{ .output = msg, .is_error = true };
        };
        if (results.items.len == 0) return .{ .output = "No matches found", .is_error = false };
        return .{ .output = results.toOwnedSlice() catch "No matches found", .is_error = false };
    };

    if (stat.kind == .file) {
        searchFile(allocator, search_path, unescaped_pattern, &results, &match_count, max_matches) catch {};
    } else {
        searchDir(allocator, search_path, unescaped_pattern, &results, &match_count, max_matches, 0) catch {};
    }

    if (results.items.len == 0) return .{ .output = "No matches found", .is_error = false };
    return .{ .output = results.toOwnedSlice() catch "No matches found", .is_error = false };
}

fn searchDir(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    pattern: []const u8,
    results: *std.ArrayList(u8),
    match_count: *usize,
    max_matches: usize,
    depth: usize,
) !void {
    if (depth > 10) return; // prevent infinite recursion
    if (match_count.* >= max_matches) return;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (match_count.* >= max_matches) return;

        // Skip hidden dirs and common noise
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules")) continue;
        if (std.mem.eql(u8, entry.name, "zig-out")) continue;
        if (std.mem.eql(u8, entry.name, "zig-cache")) continue;

        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name }) catch continue;

        switch (entry.kind) {
            .file => {
                searchFile(allocator, full_path, pattern, results, match_count, max_matches) catch continue;
            },
            .directory => {
                searchDir(allocator, full_path, pattern, results, match_count, max_matches, depth + 1) catch continue;
            },
            else => {},
        }
    }
}

fn searchFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    pattern: []const u8,
    results: *std.ArrayList(u8),
    match_count: *usize,
    max_matches: usize,
) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return;
    defer file.close();

    // Skip binary files (check first 512 bytes for null bytes)
    var probe: [512]u8 = undefined;
    const probe_len = file.read(&probe) catch return;
    for (probe[0..probe_len]) |b| {
        if (b == 0) return; // binary file, skip
    }
    file.seekTo(0) catch return;

    const content = file.readToEndAlloc(allocator, 1024 * 512) catch return;
    defer allocator.free(content);

    var line_num: usize = 1;
    var line_start: usize = 0;

    for (content, 0..) |c, i| {
        if (c == '\n' or i == content.len - 1) {
            const line_end = if (c == '\n') i else i + 1;
            const line = content[line_start..line_end];

            if (std.mem.indexOf(u8, line, pattern)) |_| {
                const entry = std.fmt.allocPrint(allocator, "{s}:{d}:{s}\n", .{
                    file_path,
                    line_num,
                    line,
                }) catch continue;
                results.appendSlice(entry) catch return;
                match_count.* += 1;
                if (match_count.* >= max_matches) return;
            }

            line_start = i + 1;
            line_num += 1;
        }
    }
}

fn executeListFiles(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const dir_path = json.extractString(input, "path") orelse ".";
    const pattern = json.extractString(input, "pattern");

    const unescaped_pattern = if (pattern) |p| json.unescape(allocator, p) catch p else null;

    // Pure Zig implementation — no shell, no injection risk
    var results = std.ArrayList(u8).init(allocator);
    var file_count: usize = 0;
    const max_files: usize = 200;

    listDir(allocator, dir_path, unescaped_pattern, &results, &file_count, max_files, 0) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "List failed: {}", .{err}) catch "list error";
        return .{ .output = msg, .is_error = true };
    };

    if (results.items.len == 0) return .{ .output = "(no files found)", .is_error = false };
    return .{ .output = results.toOwnedSlice() catch "(no files found)", .is_error = false };
}

fn listDir(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    pattern: ?[]const u8,
    results: *std.ArrayList(u8),
    file_count: *usize,
    max_files: usize,
    depth: usize,
) !void {
    if (depth > 10) return;
    if (file_count.* >= max_files) return;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (file_count.* >= max_files) return;

        // Skip hidden entries
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules")) continue;
        if (std.mem.eql(u8, entry.name, "zig-out")) continue;
        if (std.mem.eql(u8, entry.name, "zig-cache")) continue;

        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name }) catch continue;

        switch (entry.kind) {
            .file => {
                // Apply glob pattern if specified (simple suffix match)
                if (pattern) |p| {
                    if (!matchGlob(entry.name, p)) continue;
                }
                results.appendSlice(full_path) catch continue;
                results.append('\n') catch continue;
                file_count.* += 1;
            },
            .directory => {
                listDir(allocator, full_path, pattern, results, file_count, max_files, depth + 1) catch continue;
            },
            else => {},
        }
    }
}

/// Simple glob match — supports * prefix (*.zig) and * suffix (src*)
fn matchGlob(name: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;

    // *.ext pattern
    if (pattern.len > 1 and pattern[0] == '*') {
        return std.mem.endsWith(u8, name, pattern[1..]);
    }
    // prefix* pattern
    if (pattern.len > 1 and pattern[pattern.len - 1] == '*') {
        return std.mem.startsWith(u8, name, pattern[0 .. pattern.len - 1]);
    }
    // Exact match
    return std.mem.eql(u8, name, pattern);
}

// ============================================================
// Tests
// ============================================================

test "execute unknown tool" {
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{ .id = "t1", .name = "nonexistent", .input_raw = "{}" });
    try std.testing.expect(result.is_error);
    try std.testing.expectEqualStrings("Unknown tool", result.output);
}

test "bash echo" {
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
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "bash",
        .input_raw = "{\"command\":\"false\"}",
    });
    try std.testing.expect(result.is_error);
}

test "read_file" {
    const alloc = std.testing.allocator;
    // Write a temp file first
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
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_write.txt";
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const input = std.fmt.allocPrint(alloc, "{{\"path\":\"{s}\",\"content\":\"written data\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "write_file", .input_raw = input });
    try std.testing.expect(!result.is_error);

    // Verify file was written
    const f = try std.fs.cwd().openFile(tmp_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, 1024);
    defer alloc.free(content);
    try std.testing.expectEqualStrings("written data", content);
}

test "edit_file unique match" {
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("hello world");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const input = std.fmt.allocPrint(alloc,
        "{{\"path\":\"{s}\",\"old_string\":\"hello\",\"new_string\":\"goodbye\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(!result.is_error);

    // Verify
    const f = try std.fs.cwd().openFile(tmp_path, .{});
    defer f.close();
    const content = try f.readToEndAlloc(alloc, 1024);
    defer alloc.free(content);
    try std.testing.expectEqualStrings("goodbye world", content);
}

test "edit_file no match" {
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit_nomatch.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("hello world");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const input = std.fmt.allocPrint(alloc,
        "{{\"path\":\"{s}\",\"old_string\":\"NOTFOUND\",\"new_string\":\"x\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "not found") != null);
}

test "edit_file multiple matches" {
    const alloc = std.testing.allocator;
    const tmp_path = "/tmp/yoctoclaw_test_edit_multi.txt";
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll("foo bar foo");
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const input = std.fmt.allocPrint(alloc,
        "{{\"path\":\"{s}\",\"old_string\":\"foo\",\"new_string\":\"baz\"}}", .{tmp_path}) catch unreachable;
    defer alloc.free(input);
    const result = execute(alloc, .{ .id = "t1", .name = "edit_file", .input_raw = input });
    try std.testing.expect(result.is_error);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "must be unique") != null);
}

test "search no injection" {
    const alloc = std.testing.allocator;
    // This pattern would be dangerous with shell execution
    const result = execute(alloc, .{
        .id = "t1",
        .name = "search",
        .input_raw = "{\"pattern\":\"'; rm -rf /\",\"path\":\"/tmp\"}",
    });
    // Should NOT crash or execute the injected command
    // Should just return no matches (the pattern won't match anything)
    try std.testing.expect(!result.is_error or
        std.mem.indexOf(u8, result.output, "No matches") != null or
        std.mem.indexOf(u8, result.output, "Search failed") != null);
}

test "list_files no injection" {
    const alloc = std.testing.allocator;
    const result = execute(alloc, .{
        .id = "t1",
        .name = "list_files",
        .input_raw = "{\"path\":\"/tmp\",\"pattern\":\"'; rm -rf /\"}",
    });
    // Should NOT crash or execute the injected command
    try std.testing.expect(!result.is_error or
        std.mem.indexOf(u8, result.output, "no files") != null);
}

test "matchGlob" {
    try std.testing.expect(matchGlob("main.zig", "*.zig"));
    try std.testing.expect(!matchGlob("main.go", "*.zig"));
    try std.testing.expect(matchGlob("main.zig", "*"));
    try std.testing.expect(matchGlob("src_test.zig", "src*"));
    try std.testing.expect(matchGlob("main.zig", "main.zig"));
    try std.testing.expect(!matchGlob("other.zig", "main.zig"));
}
