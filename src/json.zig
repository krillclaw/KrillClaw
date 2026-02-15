const std = @import("std");
const types = @import("types.zig");
const tools_mod = @import("tools.zig");

// ============================================================
// JSON Builder — serialize Zig types to JSON
// ============================================================

/// Build a Claude Messages API request body as JSON.
pub fn buildClaudeRequest(
    allocator: std.mem.Allocator,
    config: types.Config,
    messages: []const types.Message,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();

    try w.writeAll("{\"model\":\"");
    try writeEscaped(w, config.model);
    try w.writeAll("\",\"max_tokens\":");
    try w.print("{d}", .{config.max_tokens});

    if (config.streaming) {
        try w.writeAll(",\"stream\":true");
    }

    try w.writeAll(",\"system\":\"");
    try writeEscaped(w, config.system_prompt);
    try w.writeAll("\",\"tools\":[");

    for (tools_mod.tool_definitions, 0..) |tool, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":\"");
        try writeEscaped(w, tool.name);
        try w.writeAll("\",\"description\":\"");
        try writeEscaped(w, tool.description);
        try w.writeAll("\",\"input_schema\":");
        try w.writeAll(tool.input_schema);
        try w.writeByte('}');
    }

    try w.writeAll("],\"messages\":[");

    for (messages, 0..) |msg, mi| {
        if (mi > 0) try w.writeByte(',');
        try w.writeAll("{\"role\":\"");
        try w.writeAll(msg.role.toString());
        try w.writeAll("\",\"content\":[");

        for (msg.content, 0..) |block, bi| {
            if (bi > 0) try w.writeByte(',');
            switch (block.type) {
                .text => {
                    try w.writeAll("{\"type\":\"text\",\"text\":\"");
                    try writeEscaped(w, block.text orelse "");
                    try w.writeAll("\"}");
                },
                .tool_use => {
                    const tu = block.tool_use orelse continue;
                    try w.writeAll("{\"type\":\"tool_use\",\"id\":\"");
                    try writeEscaped(w, tu.id);
                    try w.writeAll("\",\"name\":\"");
                    try writeEscaped(w, tu.name);
                    try w.writeAll("\",\"input\":");
                    try w.writeAll(tu.input_raw);
                    try w.writeByte('}');
                },
                .tool_result => {
                    try w.writeAll("{\"type\":\"tool_result\",\"tool_use_id\":\"");
                    try writeEscaped(w, block.tool_use_id orelse "");
                    try w.writeAll("\",\"content\":\"");
                    try writeEscaped(w, block.content orelse "");
                    try w.writeByte('"');
                    if (block.is_error) {
                        try w.writeAll(",\"is_error\":true");
                    }
                    try w.writeByte('}');
                },
            }
        }

        try w.writeAll("]}");
    }

    try w.writeAll("]}");
    return buf.toOwnedSlice();
}

/// Build an OpenAI-compatible request body (works for OpenAI + Ollama).
pub fn buildOpenAiRequest(
    allocator: std.mem.Allocator,
    config: types.Config,
    messages: []const types.Message,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();

    try w.writeAll("{\"model\":\"");
    try writeEscaped(w, config.model);
    try w.writeAll("\",\"max_tokens\":");
    try w.print("{d}", .{config.max_tokens});

    if (config.streaming) {
        try w.writeAll(",\"stream\":true");
    }

    // Tools (OpenAI format wraps in "function")
    try w.writeAll(",\"tools\":[");
    for (tools_mod.tool_definitions, 0..) |tool, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"type\":\"function\",\"function\":{\"name\":\"");
        try writeEscaped(w, tool.name);
        try w.writeAll("\",\"description\":\"");
        try writeEscaped(w, tool.description);
        try w.writeAll("\",\"parameters\":");
        try w.writeAll(tool.input_schema);
        try w.writeAll("}}");
    }

    try w.writeAll("],\"messages\":[");

    // System message first
    try w.writeAll("{\"role\":\"system\",\"content\":\"");
    try writeEscaped(w, config.system_prompt);
    try w.writeAll("\"}");

    for (messages) |msg| {
        try w.writeByte(',');
        try w.writeAll("{\"role\":\"");
        try w.writeAll(msg.role.toString());
        try w.writeAll("\"");

        // For assistant messages with tool calls
        var has_tool_calls = false;
        for (msg.content) |block| {
            if (block.type == .tool_use) {
                has_tool_calls = true;
                break;
            }
        }

        if (has_tool_calls) {
            try w.writeAll(",\"tool_calls\":[");
            var tc_idx: usize = 0;
            for (msg.content) |block| {
                if (block.type == .tool_use) {
                    const tu = block.tool_use orelse continue;
                    if (tc_idx > 0) try w.writeByte(',');
                    try w.writeAll("{\"id\":\"");
                    try writeEscaped(w, tu.id);
                    try w.writeAll("\",\"type\":\"function\",\"function\":{\"name\":\"");
                    try writeEscaped(w, tu.name);
                    try w.writeAll("\",\"arguments\":");
                    try w.writeAll(tu.input_raw);
                    try w.writeAll("}}");
                    tc_idx += 1;
                }
            }
            try w.writeByte(']');

            // Also include text content if any
            for (msg.content) |block| {
                if (block.type == .text) {
                    try w.writeAll(",\"content\":\"");
                    try writeEscaped(w, block.text orelse "");
                    try w.writeByte('"');
                    break;
                }
            }
        } else {
            // Regular content
            for (msg.content) |block| {
                switch (block.type) {
                    .text => {
                        try w.writeAll(",\"content\":\"");
                        try writeEscaped(w, block.text orelse "");
                        try w.writeByte('"');
                    },
                    .tool_result => {
                        // OpenAI uses role "tool" for tool results
                        // We need to close current message and start tool message
                        // This is handled by the message loop outside
                    },
                    else => {},
                }
            }
        }

        try w.writeByte('}');

        // Emit separate tool result messages for OpenAI format
        for (msg.content) |block| {
            if (block.type == .tool_result) {
                try w.writeAll(",{\"role\":\"tool\",\"tool_call_id\":\"");
                try writeEscaped(w, block.tool_use_id orelse "");
                try w.writeAll("\",\"content\":\"");
                try writeEscaped(w, block.content orelse "");
                try w.writeAll("\"}");
            }
        }
    }

    try w.writeAll("]}");
    return buf.toOwnedSlice();
}

// ============================================================
// JSON Extractors — pull values from JSON strings
// ============================================================

/// Extract string value for a given key from a JSON object.
pub fn extractString(json: []const u8, key: []const u8) ?[]const u8 {
    const kstart = findKey(json, key) orelse return null;
    var pos = kstart;

    // Skip whitespace
    while (pos < json.len and isWhitespace(json[pos])) : (pos += 1) {}

    if (pos >= json.len or json[pos] != '"') return null;
    pos += 1;

    const start = pos;
    while (pos < json.len and json[pos] != '"') {
        if (json[pos] == '\\') pos += 1;
        pos += 1;
    }
    return json[start..pos];
}

/// Extract an integer value for a given key.
pub fn extractInt(json: []const u8, key: []const u8) ?u32 {
    const kstart = findKey(json, key) orelse return null;
    var pos = kstart;

    while (pos < json.len and isWhitespace(json[pos])) : (pos += 1) {}

    var end = pos;
    while (end < json.len and json[end] >= '0' and json[end] <= '9') : (end += 1) {}

    if (end == pos) return null;
    return std.fmt.parseInt(u32, json[pos..end], 10) catch null;
}

/// Extract a boolean value for a given key.
pub fn extractBool(json: []const u8, key: []const u8) ?bool {
    const kstart = findKey(json, key) orelse return null;
    var pos = kstart;

    while (pos < json.len and isWhitespace(json[pos])) : (pos += 1) {}

    if (pos + 4 <= json.len and std.mem.eql(u8, json[pos .. pos + 4], "true")) return true;
    if (pos + 5 <= json.len and std.mem.eql(u8, json[pos .. pos + 5], "false")) return false;
    return null;
}

/// Extract a JSON object value (as raw string) for a given key.
pub fn extractObject(json: []const u8, key: []const u8) ?[]const u8 {
    const kstart = findKey(json, key) orelse return null;
    return extractBraced(json, kstart, '{', '}');
}

/// Extract a JSON array value (as raw string) for a given key.
pub fn extractArray(json: []const u8, key: []const u8) ?[]const u8 {
    const kstart = findKey(json, key) orelse return null;
    return extractBraced(json, kstart, '[', ']');
}

// ============================================================
// JSON Unescape
// ============================================================

/// Unescape JSON string escape sequences.
pub fn unescape(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '\\' and i + 1 < s.len) {
            switch (s[i + 1]) {
                'n' => try out.append('\n'),
                'r' => try out.append('\r'),
                't' => try out.append('\t'),
                '\\' => try out.append('\\'),
                '"' => try out.append('"'),
                '/' => try out.append('/'),
                else => {
                    try out.append(s[i]);
                    try out.append(s[i + 1]);
                },
            }
            i += 2;
        } else {
            try out.append(s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

// ============================================================
// Helpers
// ============================================================

fn writeEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Find the position right after "key": in JSON.
fn findKey(json: []const u8, key: []const u8) ?usize {
    // Search for "key" followed by :
    var pos: usize = 0;
    while (pos + key.len + 3 <= json.len) {
        if (json[pos] == '"' and
            pos + 1 + key.len < json.len and
            std.mem.eql(u8, json[pos + 1 .. pos + 1 + key.len], key) and
            json[pos + 1 + key.len] == '"')
        {
            var after = pos + 2 + key.len;
            while (after < json.len and isWhitespace(json[after])) : (after += 1) {}
            if (after < json.len and json[after] == ':') {
                return after + 1;
            }
        }
        pos += 1;
    }
    return null;
}

fn extractBraced(json: []const u8, start: usize, open: u8, close: u8) ?[]const u8 {
    var pos = start;
    while (pos < json.len and isWhitespace(json[pos])) : (pos += 1) {}
    if (pos >= json.len or json[pos] != open) return null;

    var depth: u32 = 0;
    var in_string = false;
    var i = pos;
    while (i < json.len) : (i += 1) {
        if (json[i] == '\\' and in_string) {
            i += 1;
            continue;
        }
        if (json[i] == '"') in_string = !in_string;
        if (!in_string) {
            if (json[i] == open) depth += 1;
            if (json[i] == close) {
                depth -= 1;
                if (depth == 0) return json[pos .. i + 1];
            }
        }
    }
    return null;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// ============================================================
// Tests
// ============================================================

test "extractString" {
    const json = "{\"name\":\"hello\",\"value\":\"world\"}";
    try std.testing.expectEqualStrings("hello", extractString(json, "name").?);
    try std.testing.expectEqualStrings("world", extractString(json, "value").?);
    try std.testing.expect(extractString(json, "missing") == null);
}

test "extractInt" {
    const json = "{\"count\":42,\"size\":0}";
    try std.testing.expectEqual(@as(u32, 42), extractInt(json, "count").?);
    try std.testing.expectEqual(@as(u32, 0), extractInt(json, "size").?);
}

test "extractObject" {
    const json = "{\"data\":{\"a\":1,\"b\":2},\"other\":true}";
    try std.testing.expectEqualStrings("{\"a\":1,\"b\":2}", extractObject(json, "data").?);
}

test "extractArray" {
    const json = "{\"items\":[1,2,3]}";
    try std.testing.expectEqualStrings("[1,2,3]", extractArray(json, "items").?);
}

test "extractString with escapes" {
    const json_str = "{\"key\":\"hello\\nworld\"}";
    const val = extractString(json_str, "key").?;
    try std.testing.expectEqualStrings("hello\\nworld", val);
}

test "extractString nested key" {
    // Known limitation: finds first occurrence regardless of depth
    const json_str = "{\"a\":{\"id\":\"inner\"},\"id\":\"outer\"}";
    const val = extractString(json_str, "id").?;
    // Should find "inner" (first occurrence)
    try std.testing.expectEqualStrings("inner", val);
}

test "extractBool" {
    const json_str = "{\"flag\":true,\"other\":false}";
    try std.testing.expectEqual(true, extractBool(json_str, "flag").?);
    try std.testing.expectEqual(false, extractBool(json_str, "other").?);
    try std.testing.expect(extractBool(json_str, "missing") == null);
}

test "unescape sequences" {
    const alloc = std.testing.allocator;

    const r1 = try unescape(alloc, "hello\\nworld");
    defer alloc.free(r1);
    try std.testing.expectEqualStrings("hello\nworld", r1);

    const r2 = try unescape(alloc, "tab\\there");
    defer alloc.free(r2);
    try std.testing.expectEqualStrings("tab\there", r2);

    const r3 = try unescape(alloc, "quote\\\"end");
    defer alloc.free(r3);
    try std.testing.expectEqualStrings("quote\"end", r3);

    const r4 = try unescape(alloc, "back\\\\slash");
    defer alloc.free(r4);
    try std.testing.expectEqualStrings("back\\slash", r4);
}

test "buildClaudeRequest basic" {
    const alloc = std.testing.allocator;
    var content = [_]types.ContentBlock{.{
        .type = .text,
        .text = "hello",
    }};
    var msgs = [_]types.Message{.{
        .role = .user,
        .content = &content,
    }};
    const config = types.Config{ .streaming = false };
    const result = try buildClaudeRequest(alloc, config, &msgs);
    defer alloc.free(result);

    // Verify key structural elements
    try std.testing.expect(std.mem.indexOf(u8, result, "\"model\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"messages\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"role\":\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"text\":\"hello\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"tools\":[") != null);
    // Should NOT have stream:true when streaming=false
    try std.testing.expect(std.mem.indexOf(u8, result, "\"stream\":true") == null);
}

test "buildClaudeRequest with tool_result" {
    const alloc = std.testing.allocator;
    var content = [_]types.ContentBlock{.{
        .type = .tool_result,
        .tool_use_id = "toolu_123",
        .content = "file contents here",
    }};
    var msgs = [_]types.Message{.{
        .role = .user,
        .content = &content,
    }};
    const config = types.Config{ .streaming = false };
    const result = try buildClaudeRequest(alloc, config, &msgs);
    defer alloc.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"tool_use_id\":\"toolu_123\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"type\":\"tool_result\"") != null);
}

test "buildOpenAiRequest basic" {
    const alloc = std.testing.allocator;
    var content = [_]types.ContentBlock{.{
        .type = .text,
        .text = "hello",
    }};
    var msgs = [_]types.Message{.{
        .role = .user,
        .content = &content,
    }};
    const config = types.Config{ .provider = .openai, .streaming = false };
    const result = try buildOpenAiRequest(alloc, config, &msgs);
    defer alloc.free(result);

    // System message should come first
    try std.testing.expect(std.mem.indexOf(u8, result, "\"role\":\"system\"") != null);
    // Should have function-style tools
    try std.testing.expect(std.mem.indexOf(u8, result, "\"type\":\"function\"") != null);
}
