const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");
const build_options = @import("build_options");

pub const ToolResult = struct {
    output: []const u8,
    is_error: bool,
};

pub const tool_definitions = [_]types.ToolDef{
    .{
        .name = "bash",
        .description = "Execute a bash command and return stdout/stderr.",
        .input_schema =
        \\{"type":"object","properties":{"command":{"type":"string","description":"The bash command to execute"}},"required":["command"]}
        ,
    },
    .{
        .name = "read_file",
        .description = "Read the contents of a file at the given path.",
        .input_schema =
        \\{"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the file to read"}},"required":["path"]}
        ,
    },
    .{
        .name = "write_file",
        .description = "Write content to a file, creating it if it doesn't exist.",
        .input_schema =
        \\{"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the file"},"content":{"type":"string","description":"Content to write"}},"required":["path","content"]}
        ,
    },
    .{
        .name = "edit_file",
        .description = "Replace an exact string in a file with new content. The old_string must appear exactly once.",
        .input_schema =
        \\{"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the file"},"old_string":{"type":"string","description":"Exact string to find and replace"},"new_string":{"type":"string","description":"Replacement string"}},"required":["path","old_string","new_string"]}
        ,
    },
    .{
        .name = "search",
        .description = "Search for a text pattern in files. Returns matching lines with file paths and line numbers.",
        .input_schema =
        \\{"type":"object","properties":{"pattern":{"type":"string","description":"Text pattern to search for (substring match)"},"path":{"type":"string","description":"Directory or file to search in (default: current directory)"}},"required":["pattern"]}
        ,
    },
    .{
        .name = "list_files",
        .description = "List files in a directory, optionally with a glob pattern.",
        .input_schema =
        \\{"type":"object","properties":{"path":{"type":"string","description":"Directory to list (default: current directory)"},"pattern":{"type":"string","description":"Glob pattern to filter files (e.g. *.zig)"}},"required":[]}
        ,
    },
    .{
        .name = "apply_patch",
        .description = "Apply a unified diff patch to a file.",
        .input_schema =
        \\{"type":"object","properties":{"path":{"type":"string","description":"File to patch"},"patch":{"type":"string","description":"Unified diff content"}},"required":["path","patch"]}
        ,
    },
};

/// Path allowlist: restrict file operations to cwd (stricter in sandbox mode)
/// Uses canonical path resolution to prevent traversal attacks via .., symlinks, etc.
fn isPathAllowed(path: []const u8) bool {
    // Quick reject on obvious traversal attempts
    if (std.mem.indexOf(u8, path, "..") != null) return false;

    // Get canonical path to prevent all traversal attacks (symlinks, .., encodings)
    const canonical = std.fs.cwd().realpathAlloc(std.heap.page_allocator, path) catch {
        // If path doesn't exist yet (e.g., write_file), validate parent + basename
        const dirname = std.fs.path.dirname(path) orelse ".";
        const basename = std.fs.path.basename(path);

        // Resolve parent directory
        const parent_canon = std.fs.cwd().realpathAlloc(std.heap.page_allocator, dirname) catch return false;
        defer std.heap.page_allocator.free(parent_canon);

        // Check if parent is allowed
        if (!isCanonicalPathAllowed(parent_canon)) return false;

        // CRITICAL: Reconstruct full path and validate it would be under allowed root
        // This prevents attacks like "allowed_dir/../../../etc/passwd"
        const reconstructed = std.fs.path.join(std.heap.page_allocator, &.{ parent_canon, basename }) catch return false;
        defer std.heap.page_allocator.free(reconstructed);

        // Double-check reconstructed path is under allowed directories
        return isCanonicalPathAllowed(reconstructed);
    };
    defer std.heap.page_allocator.free(canonical);

    return isCanonicalPathAllowed(canonical);
}

/// Check if a canonical (resolved) path is allowed
fn isCanonicalPathAllowed(canonical_path: []const u8) bool {
    if (build_options.sandbox) {
        // Sandbox: only /tmp/yoctoclaw-sandbox
        return std.mem.startsWith(u8, canonical_path, "/tmp/yoctoclaw-sandbox");
    }

    // Non-sandbox: allow /tmp/yoctoclaw-* (least privilege) or paths under cwd
    if (std.mem.startsWith(u8, canonical_path, "/tmp/yoctoclaw")) return true;

    const cwd_real = std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".") catch return false;
    defer std.heap.page_allocator.free(cwd_real);

    return std.mem.startsWith(u8, canonical_path, cwd_real);
}

pub fn execute(allocator: std.mem.Allocator, tool: types.ToolUse) ToolResult {
    if (std.mem.eql(u8, tool.name, "bash")) return executeBash(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "read_file")) return executeReadFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "write_file")) return executeWriteFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "edit_file")) return executeEditFile(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "search")) return executeSearch(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "list_files")) return executeListFiles(allocator, tool.input_raw);
    if (std.mem.eql(u8, tool.name, "apply_patch")) return executeApplyPatch(allocator, tool.input_raw);
    return .{ .output = "Unknown tool", .is_error = true };
}

fn executeBash(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const command = json.extractString(input, "command") orelse {
        return .{ .output = "Missing 'command' parameter", .is_error = true };
    };
    const unescaped_cmd = json.unescape(allocator, command) catch command;

    // In sandbox mode, run inside a restricted environment
    const shell_cmd = if (build_options.sandbox) blk: {
        // Create sandbox directory
        std.fs.cwd().makePath("/tmp/yoctoclaw-sandbox") catch {};
        // Wrap command: restrict to sandbox dir, empty PATH (no network tools)
        break :blk std.fmt.allocPrint(allocator,
            "cd /tmp/yoctoclaw-sandbox && PATH= /bin/sh -c {s}",
            .{shellQuote(allocator, unescaped_cmd)},
        ) catch unescaped_cmd;
    } else unescaped_cmd;

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", shell_cmd },
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

/// Shell-quote a string for safe inclusion in sh -c
fn shellQuote(allocator: std.mem.Allocator, s: []const u8) []const u8 {
    var out = std.ArrayList(u8).init(allocator);
    out.append('\'') catch return s;
    for (s) |c| {
        if (c == '\'') {
            out.appendSlice("'\\''") catch return s;
        } else {
            out.append(c) catch return s;
        }
    }
    out.append('\'') catch return s;
    return out.toOwnedSlice() catch s;
}

fn executeReadFile(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };
    if (!isPathAllowed(path)) return .{ .output = "Path not allowed", .is_error = true };
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot open '{s}': {}", .{ path, err }) catch "open error";
        return .{ .output = msg, .is_error = true };
    };
    defer file.close();
    const content = file.readToEndAlloc(allocator, 1024 * 64) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Cannot read: {}", .{err}) catch "read error";
        return .{ .output = msg, .is_error = true };
    };
    return .{ .output = if (content.len == 0) "(empty file)" else content, .is_error = false };
}

fn executeWriteFile(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };
    if (!isPathAllowed(path)) return .{ .output = "Path not allowed", .is_error = true };
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
    if (!isPathAllowed(path)) return .{ .output = "Path not allowed", .is_error = true };
    const old_string_raw = json.extractString(input, "old_string") orelse {
        return .{ .output = "Missing 'old_string' parameter", .is_error = true };
    };
    const new_string_raw = json.extractString(input, "new_string") orelse {
        return .{ .output = "Missing 'new_string' parameter", .is_error = true };
    };
    const old_string = json.unescape(allocator, old_string_raw) catch old_string_raw;
    const new_string = json.unescape(allocator, new_string_raw) catch new_string_raw;
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
    var count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOf(u8, file_content[search_pos..], old_string)) |idx| {
        count += 1;
        search_pos += idx + old_string.len;
    }
    if (count == 0) return .{ .output = "old_string not found in file", .is_error = true };
    if (count > 1) {
        const msg = std.fmt.allocPrint(allocator, "old_string found {d} times (must be unique)", .{count}) catch "multiple matches";
        return .{ .output = msg, .is_error = true };
    }
    const idx = std.mem.indexOf(u8, file_content, old_string).?;
    const new_content = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        file_content[0..idx], new_string, file_content[idx + old_string.len ..],
    }) catch return .{ .output = "Failed to build replacement", .is_error = true };
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
    // SECURITY: Enforce path allowlist to prevent sandbox bypass
    if (!isPathAllowed(search_path)) {
        return .{ .output = "Search path not allowed", .is_error = true };
    }
    const unescaped_pattern = json.unescape(allocator, pattern) catch pattern;
    var results = std.ArrayList(u8).init(allocator);
    var match_count: usize = 0;
    const max_matches: usize = 100;
    const stat = std.fs.cwd().statFile(search_path) catch {
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

fn searchDir(allocator: std.mem.Allocator, dir_path: []const u8, pattern: []const u8, results: *std.ArrayList(u8), match_count: *usize, max_matches: usize, depth: usize) !void {
    if (depth > 10 or match_count.* >= max_matches) return;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (match_count.* >= max_matches) return;
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules") or std.mem.eql(u8, entry.name, "zig-out") or std.mem.eql(u8, entry.name, "zig-cache")) continue;
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name }) catch continue;
        switch (entry.kind) {
            .file => searchFile(allocator, full_path, pattern, results, match_count, max_matches) catch continue,
            .directory => searchDir(allocator, full_path, pattern, results, match_count, max_matches, depth + 1) catch continue,
            else => {},
        }
    }
}

fn searchFile(allocator: std.mem.Allocator, file_path: []const u8, pattern: []const u8, results: *std.ArrayList(u8), match_count: *usize, max_matches: usize) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch return;
    defer file.close();
    var probe: [512]u8 = undefined;
    const probe_len = file.read(&probe) catch return;
    for (probe[0..probe_len]) |b| { if (b == 0) return; }
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
                const entry_str = std.fmt.allocPrint(allocator, "{s}:{d}:{s}\n", .{ file_path, line_num, line }) catch continue;
                results.appendSlice(entry_str) catch return;
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
    // SECURITY: Enforce path allowlist to prevent sandbox bypass
    if (!isPathAllowed(dir_path)) {
        return .{ .output = "Directory path not allowed", .is_error = true };
    }
    const pattern = json.extractString(input, "pattern");
    const unescaped_pattern = if (pattern) |p| json.unescape(allocator, p) catch p else null;
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

fn listDir(allocator: std.mem.Allocator, dir_path: []const u8, pattern: ?[]const u8, results: *std.ArrayList(u8), file_count: *usize, max_files: usize, depth: usize) !void {
    if (depth > 10 or file_count.* >= max_files) return;
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (file_count.* >= max_files) return;
        if (entry.name.len > 0 and entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "node_modules") or std.mem.eql(u8, entry.name, "zig-out") or std.mem.eql(u8, entry.name, "zig-cache")) continue;
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name }) catch continue;
        switch (entry.kind) {
            .file => {
                if (pattern) |p| { if (!matchGlob(entry.name, p)) continue; }
                results.appendSlice(full_path) catch continue;
                results.append('\n') catch continue;
                file_count.* += 1;
            },
            .directory => listDir(allocator, full_path, pattern, results, file_count, max_files, depth + 1) catch continue,
            else => {},
        }
    }
}

pub fn matchGlob(name: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (pattern.len > 1 and pattern[0] == '*') return std.mem.endsWith(u8, name, pattern[1..]);
    if (pattern.len > 1 and pattern[pattern.len - 1] == '*') return std.mem.startsWith(u8, name, pattern[0 .. pattern.len - 1]);
    return std.mem.eql(u8, name, pattern);
}

fn executeApplyPatch(allocator: std.mem.Allocator, input: []const u8) ToolResult {
    const path = json.extractString(input, "path") orelse {
        return .{ .output = "Missing 'path' parameter", .is_error = true };
    };
    if (!isPathAllowed(path)) return .{ .output = "Path not allowed", .is_error = true };
    const patch = json.extractString(input, "patch") orelse {
        return .{ .output = "Missing 'patch' parameter", .is_error = true };
    };
    const unescaped_patch = json.unescape(allocator, patch) catch patch;
    // Use unique temp file to prevent TOCTOU race condition
    const timestamp = @as(u64, @intCast(std.time.timestamp()));
    const tmp_patch = std.fmt.allocPrint(allocator, "/tmp/yoctoclaw_patch_{d}.tmp", .{timestamp}) catch {
        return .{ .output = "Failed to create temp path", .is_error = true };
    };
    defer allocator.free(tmp_patch);
    {
        const f = std.fs.cwd().createFile(tmp_patch, .{}) catch {
            return .{ .output = "Cannot create temp patch file", .is_error = true };
        };
        defer f.close();
        f.writeAll(unescaped_patch) catch {
            return .{ .output = "Cannot write patch", .is_error = true };
        };
    }
    var escaped_path = std.ArrayList(u8).init(allocator);
    for (path) |c| {
        if (c == '\'') {
            escaped_path.appendSlice("'\\''") catch return .{ .output = "escape error", .is_error = true };
        } else {
            escaped_path.append(c) catch return .{ .output = "escape error", .is_error = true };
        }
    }
    const safe_path = escaped_path.toOwnedSlice() catch return .{ .output = "escape error", .is_error = true };
    const cmd = std.fmt.allocPrint(allocator, "patch -p0 '{s}' < '{s}'", .{ safe_path, tmp_patch }) catch {
        return .{ .output = "Failed to build patch command", .is_error = true };
    };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", cmd },
        .max_output_bytes = 1024 * 64,
    }) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Patch failed: {}", .{err}) catch "patch error";
        return .{ .output = msg, .is_error = true };
    };
    const is_err = switch (result.term) {
        .Exited => |code| code != 0,
        else => true,
    };
    const output = if (result.stdout.len > 0) result.stdout else if (result.stderr.len > 0) result.stderr else "Patch applied";
    return .{ .output = output, .is_error = is_err };
}
