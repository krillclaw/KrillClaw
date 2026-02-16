const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");

/// SSE (Server-Sent Events) streaming parser for Claude API responses.
///
/// Parses the chunked event stream and calls back with typed events,
/// allowing real-time token display.
pub const StreamParser = struct {
    allocator: std.mem.Allocator,
    provider: types.Provider = .claude,
    line_buf: std.ArrayList(u8),
    event_type: ?[]const u8 = null,

    // Accumulated state for building the final response
    content_blocks: std.ArrayList(types.ContentBlock),
    current_text: std.ArrayList(u8),
    current_tool_id: ?[]const u8 = null,
    current_tool_name: ?[]const u8 = null,
    current_tool_input: std.ArrayList(u8),
    stop_reason: types.StopReason = .unknown,
    input_tokens: u32 = 0,
    output_tokens: u32 = 0,
    response_id: ?[]const u8 = null,

    // Current content block index and type
    block_index: u32 = 0,
    in_tool_use: bool = false,
    current_tool_index: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) StreamParser {
        return initWithProvider(allocator, .claude);
    }

    pub fn initWithProvider(allocator: std.mem.Allocator, provider: types.Provider) StreamParser {
        return .{
            .allocator = allocator,
            .provider = provider,
            .line_buf = std.ArrayList(u8).init(allocator),
            .content_blocks = std.ArrayList(types.ContentBlock).init(allocator),
            .current_text = std.ArrayList(u8).init(allocator),
            .current_tool_input = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *StreamParser) void {
        self.line_buf.deinit();
        self.content_blocks.deinit();
        self.current_text.deinit();
        self.current_tool_input.deinit();
    }

    /// Feed raw bytes from the HTTP response. Calls on_text for each text delta.
    /// Returns true when the message is complete.
    pub fn feed(self: *StreamParser, data: []const u8, on_text: ?*const fn ([]const u8) void) !bool {
        for (data) |byte| {
            if (byte == '\n') {
                const line = self.line_buf.items;

                if (line.len == 0) {
                    // Empty line = end of event, process it
                    if (self.event_type) |old_event| {
                        // Event was already processed in data line, free it
                        self.allocator.free(old_event);
                    }
                    self.event_type = null;
                } else if (std.mem.startsWith(u8, line, "event: ")) {
                    // Free previous event_type before allocating new one
                    if (self.event_type) |old_event| {
                        self.allocator.free(old_event);
                    }
                    self.event_type = try self.allocator.dupe(u8, line[7..]);
                } else if (std.mem.startsWith(u8, line, "data: ")) {
                    const event_data = line[6..];
                    const done = switch (self.provider) {
                        .claude => try self.processEvent(event_data, on_text),
                        .openai, .ollama => try self.processOpenAiEvent(event_data, on_text),
                    };
                    if (done) return true;
                }

                self.line_buf.clearRetainingCapacity();
            } else if (byte != '\r') {
                try self.line_buf.append(byte);
            }
        }
        return false;
    }

    fn processEvent(self: *StreamParser, data: []const u8, on_text: ?*const fn ([]const u8) void) !bool {
        const event_type = self.event_type orelse return false;

        if (std.mem.eql(u8, event_type, "message_start")) {
            // Extract message ID and usage — dupe since data points into line_buf
            if (json.extractString(data, "id")) |id_str|
                self.response_id = try self.allocator.dupe(u8, id_str)
            else
                self.response_id = null;
            if (json.extractObject(data, "usage")) |usage| {
                self.input_tokens = json.extractInt(usage, "input_tokens") orelse 0;
            }
        } else if (std.mem.eql(u8, event_type, "content_block_start")) {
            self.block_index = json.extractInt(data, "index") orelse self.block_index;
            // Extract type from nested content_block object to avoid matching top-level "type"
            const cb_obj = json.extractObject(data, "content_block");
            const block_type = if (cb_obj) |cb| json.extractString(cb, "type") else json.extractString(data, "type");

            if (block_type) |bt| {
                if (std.mem.eql(u8, bt, "tool_use")) {
                    // Starting a tool use block — save ID and name
                    self.in_tool_use = true;
                    // Flush any accumulated text
                    try self.flushText();
                    // Extract from content_block sub-object if available
                    const src = cb_obj orelse data;
                    // Immediately dupe these strings — data points into line_buf
                    // which gets cleared on the next line
                    self.current_tool_id = if (json.extractString(src, "id")) |id|
                        try self.allocator.dupe(u8, id)
                    else
                        null;
                    self.current_tool_name = if (json.extractString(src, "name")) |name|
                        try self.allocator.dupe(u8, name)
                    else
                        null;
                    self.current_tool_input.clearRetainingCapacity();
                } else {
                    self.in_tool_use = false;
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_delta")) {
            if (self.in_tool_use) {
                // Accumulate tool input JSON
                if (json.extractString(data, "partial_json")) |partial| {
                    try self.current_tool_input.appendSlice(partial);
                }
            } else {
                // Text delta
                if (json.extractString(data, "text")) |text| {
                    try self.current_text.appendSlice(text);
                    if (on_text) |callback| {
                        callback(text);
                    }
                }
            }
        } else if (std.mem.eql(u8, event_type, "content_block_stop")) {
            if (self.in_tool_use) {
                try self.flushToolUse();
            } else {
                try self.flushText();
            }
        } else if (std.mem.eql(u8, event_type, "message_delta")) {
            const stop_str = json.extractString(data, "stop_reason") orelse "";
            self.stop_reason = if (std.mem.eql(u8, stop_str, "end_turn"))
                .end_turn
            else if (std.mem.eql(u8, stop_str, "tool_use"))
                .tool_use
            else if (std.mem.eql(u8, stop_str, "max_tokens"))
                .max_tokens
            else
                .unknown;

            if (json.extractObject(data, "usage")) |usage| {
                self.output_tokens = json.extractInt(usage, "output_tokens") orelse 0;
            }
        } else if (std.mem.eql(u8, event_type, "message_stop")) {
            // Flush any remaining text
            try self.flushText();
            return true;
        }

        return false;
    }


    /// Process an OpenAI-format SSE data line.
    /// OpenAI sends: data: {"id":"...","choices":[{"delta":{"content":"text"},...}],...}
    /// End signal: data: [DONE]
    fn processOpenAiEvent(self: *StreamParser, data: []const u8, on_text: ?*const fn ([]const u8) void) !bool {
        // Check for stream termination
        if (std.mem.eql(u8, data, "[DONE]")) {
            try self.flushText();
            if (self.in_tool_use) try self.flushToolUse();
            return true;
        }

        // Extract response ID
        if (self.response_id == null) {
            if (json.extractString(data, "id")) |id_str|
                self.response_id = try self.allocator.dupe(u8, id_str);
        }

        // Usage (may appear in final chunk)
        if (json.extractObject(data, "usage")) |usage| {
            if (json.extractInt(usage, "prompt_tokens")) |pt| self.input_tokens = pt;
            if (json.extractInt(usage, "completion_tokens")) |ct| self.output_tokens = ct;
        }

        // Extract choices array, then first choice object
        const choices = json.extractArray(data, "choices") orelse return false;

        // Check finish_reason
        if (json.extractString(choices, "finish_reason")) |reason| {
            if (std.mem.eql(u8, reason, "stop")) {
                self.stop_reason = .end_turn;
            } else if (std.mem.eql(u8, reason, "tool_calls")) {
                self.stop_reason = .tool_use;
            } else if (std.mem.eql(u8, reason, "length")) {
                self.stop_reason = .max_tokens;
            }
        }

        // Extract delta object
        const delta = json.extractObject(choices, "delta") orelse return false;

        // Check for tool_calls in delta
        if (json.extractArray(delta, "tool_calls")) |tool_calls| {
            // OpenAI streams tool_calls as an array with indexed elements.
            // Each element has an "index" field identifying which tool call it belongs to.
            // We iterate all objects in the array to handle multiple tool calls.
            var tc_pos: usize = 0;
            while (tc_pos < tool_calls.len) : (tc_pos += 1) {
                if (tool_calls[tc_pos] != '{') continue;

                // Extract this tool call object
                var depth: u32 = 0;
                var in_str = false;
                var tc_end = tc_pos;
                while (tc_end < tool_calls.len) : (tc_end += 1) {
                    if (tool_calls[tc_end] == '\\' and in_str) {
                        tc_end += 1;
                        continue;
                    }
                    if (tool_calls[tc_end] == '"') in_str = !in_str;
                    if (!in_str) {
                        if (tool_calls[tc_end] == '{') depth += 1;
                        if (tool_calls[tc_end] == '}') {
                            depth -= 1;
                            if (depth == 0) break;
                        }
                    }
                }

                const tc_obj = tool_calls[tc_pos .. tc_end + 1];
                const tc_index = json.extractInt(tc_obj, "index") orelse 0;

                // If this is a different tool call index, flush the previous one
                if (self.in_tool_use and self.current_tool_index != null and self.current_tool_index.? != tc_index) {
                    try self.flushToolUse();
                }

                if (!self.in_tool_use) {
                    try self.flushText();
                    self.in_tool_use = true;
                    self.current_tool_index = tc_index;
                    self.current_tool_input.clearRetainingCapacity();
                }

                // Extract function info if present (first chunk has id + function.name)
                if (json.extractString(tc_obj, "id")) |id| {
                    if (self.current_tool_id) |old| self.allocator.free(old);
                    self.current_tool_id = try self.allocator.dupe(u8, id);
                }
                if (json.extractObject(tc_obj, "function")) |func| {
                    if (json.extractString(func, "name")) |name| {
                        if (self.current_tool_name) |old| self.allocator.free(old);
                        self.current_tool_name = try self.allocator.dupe(u8, name);
                    }
                    if (json.extractString(func, "arguments")) |args| {
                        try self.current_tool_input.appendSlice(args);
                    }
                }

                tc_pos = tc_end;
            }
        } else {
            // Text content delta
            if (self.in_tool_use) {
                // Tool call ended, text starting
                try self.flushToolUse();
            }
            if (json.extractString(delta, "content")) |text| {
                if (text.len > 0) {
                    try self.current_text.appendSlice(text);
                    if (on_text) |callback| {
                        callback(text);
                    }
                }
            }
        }

        return false;
    }

    fn flushText(self: *StreamParser) !void {
        if (self.current_text.items.len > 0) {
            try self.content_blocks.append(.{
                .type = .text,
                .text = try self.allocator.dupe(u8, self.current_text.items),
            });
            self.current_text.clearRetainingCapacity();
        }
    }

    fn flushToolUse(self: *StreamParser) !void {
        const input = if (self.current_tool_input.items.len > 0)
            try self.allocator.dupe(u8, self.current_tool_input.items)
        else
            "{}";

        // current_tool_id and current_tool_name are already owned copies
        // (duped in content_block_start handler), so use them directly
        try self.content_blocks.append(.{
            .type = .tool_use,
            .tool_use = .{
                .id = self.current_tool_id orelse "",
                .name = self.current_tool_name orelse "",
                .input_raw = input,
            },
        });
        self.current_tool_id = null;
        self.current_tool_name = null;
        self.current_tool_input.clearRetainingCapacity();
        self.in_tool_use = false;
        self.current_tool_index = null;
    }

    /// Build the final ApiResponse from accumulated stream events.
    pub fn toResponse(self: *StreamParser) !types.ApiResponse {
        return .{
            .id = try self.allocator.dupe(u8, self.response_id orelse ""),
            .stop_reason = self.stop_reason,
            .content = try self.content_blocks.toOwnedSlice(),
            .input_tokens = self.input_tokens,
            .output_tokens = self.output_tokens,
        };
    }
};

// ============================================================
// Tests
// ============================================================

const text_only_sse =
    "event: message_start\n" ++
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_test\",\"usage\":{\"input_tokens\":50}}}\n" ++
    "\n" ++
    "event: content_block_start\n" ++
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\"}}\n" ++
    "\n" ++
    "event: content_block_delta\n" ++
    "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello world\"}}\n" ++
    "\n" ++
    "event: content_block_stop\n" ++
    "data: {\"type\":\"content_block_stop\",\"index\":0}\n" ++
    "\n" ++
    "event: message_delta\n" ++
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":25}}\n" ++
    "\n" ++
    "event: message_stop\n" ++
    "data: {\"type\":\"message_stop\"}\n" ++
    "\n";

const tool_use_sse =
    "event: message_start\n" ++
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_tool\",\"usage\":{\"input_tokens\":100}}}\n" ++
    "\n" ++
    "event: content_block_start\n" ++
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\"}}\n" ++
    "\n" ++
    "event: content_block_delta\n" ++
    "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Let me check\"}}\n" ++
    "\n" ++
    "event: content_block_stop\n" ++
    "data: {\"type\":\"content_block_stop\",\"index\":0}\n" ++
    "\n" ++
    "event: content_block_start\n" ++
    "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_abc\",\"name\":\"bash\"}}\n" ++
    "\n" ++
    "event: content_block_delta\n" ++
    "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"command\"}}\n" ++
    "\n" ++
    "event: content_block_delta\n" ++
    "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\":\\\"ls\\\"\"}}\n" ++
    "\n" ++
    "event: content_block_delta\n" ++
    "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"}\"}}\n" ++
    "\n" ++
    "event: content_block_stop\n" ++
    "data: {\"type\":\"content_block_stop\",\"index\":1}\n" ++
    "\n" ++
    "event: message_delta\n" ++
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":40}}\n" ++
    "\n" ++
    "event: message_stop\n" ++
    "data: {\"type\":\"message_stop\"}\n" ++
    "\n";

test "parse text-only SSE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.init(alloc);
    defer parser.deinit();

    const done = try parser.feed(text_only_sse, null);
    try std.testing.expect(done);

    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(usize, 1), resp.content.len);
    try std.testing.expectEqual(types.ContentType.text, resp.content[0].type);
    try std.testing.expectEqualStrings("Hello world", resp.content[0].text.?);
    try std.testing.expectEqual(types.StopReason.end_turn, resp.stop_reason);
}

test "parse tool_use SSE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.init(alloc);
    defer parser.deinit();

    const done = try parser.feed(tool_use_sse, null);
    try std.testing.expect(done);

    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(usize, 2), resp.content.len);
    // First block: text
    try std.testing.expectEqual(types.ContentType.text, resp.content[0].type);
    try std.testing.expectEqualStrings("Let me check", resp.content[0].text.?);
    // Second block: tool_use
    try std.testing.expectEqual(types.ContentType.tool_use, resp.content[1].type);
    const tu = resp.content[1].tool_use.?;
    try std.testing.expectEqualStrings("toolu_abc", tu.id);
    try std.testing.expectEqualStrings("bash", tu.name);
    try std.testing.expectEqual(types.StopReason.tool_use, resp.stop_reason);
}

test "parse token counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.init(alloc);
    defer parser.deinit();

    _ = try parser.feed(text_only_sse, null);
    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(u32, 50), resp.input_tokens);
    try std.testing.expectEqual(@as(u32, 25), resp.output_tokens);
}

test "streaming callback fires" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.init(alloc);
    defer parser.deinit();

    var callback_called = false;
    const S = struct {
        var called: *bool = undefined;
        fn cb(_: []const u8) void {
            called.* = true;
        }
    };
    S.called = &callback_called;
    _ = try parser.feed(text_only_sse, &S.cb);
    try std.testing.expect(callback_called);
}

test "chunked feed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.init(alloc);
    defer parser.deinit();

    // Feed one byte at a time
    var done = false;
    for (text_only_sse) |byte| {
        done = try parser.feed(&.{byte}, null);
        if (done) break;
    }
    try std.testing.expect(done);

    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(usize, 1), resp.content.len);
    try std.testing.expectEqualStrings("Hello world", resp.content[0].text.?);
}

const openai_text_sse =
    "data: {\"id\":\"chatcmpl-abc\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"index\":0,\"finish_reason\":null}]}\n" ++
    "\n" ++
    "data: {\"id\":\"chatcmpl-abc\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0,\"finish_reason\":null}]}\n" ++
    "\n" ++
    "data: {\"id\":\"chatcmpl-abc\",\"choices\":[{\"delta\":{\"content\":\" world\"},\"index\":0,\"finish_reason\":null}]}\n" ++
    "\n" ++
    "data: {\"id\":\"chatcmpl-abc\",\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}\n" ++
    "\n" ++
    "data: [DONE]\n" ++
    "\n";

test "parse OpenAI text streaming" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.initWithProvider(alloc, .openai);
    defer parser.deinit();

    const done = try parser.feed(openai_text_sse, null);
    try std.testing.expect(done);

    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(usize, 1), resp.content.len);
    try std.testing.expectEqual(types.ContentType.text, resp.content[0].type);
    try std.testing.expectEqualStrings("Hello world", resp.content[0].text.?);
    try std.testing.expectEqual(types.StopReason.end_turn, resp.stop_reason);
    try std.testing.expectEqual(@as(u32, 10), resp.input_tokens);
    try std.testing.expectEqual(@as(u32, 5), resp.output_tokens);
}

const openai_tool_sse =
    "data: {\"id\":\"chatcmpl-xyz\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"index\":0,\"id\":\"call_abc\",\"type\":\"function\",\"function\":{\"name\":\"bash\",\"arguments\":\"\"}}]},\"index\":0,\"finish_reason\":null}]}\n" ++
    "\n" ++
    "data: {\"id\":\"chatcmpl-xyz\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"command\\\":\\\"ls\\\"}\"}}]},\"index\":0,\"finish_reason\":null}]}\n" ++
    "\n" ++
    "data: {\"id\":\"chatcmpl-xyz\",\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"tool_calls\"}]}\n" ++
    "\n" ++
    "data: [DONE]\n" ++
    "\n";

test "parse OpenAI tool_calls streaming" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var parser = StreamParser.initWithProvider(alloc, .openai);
    defer parser.deinit();

    const done = try parser.feed(openai_tool_sse, null);
    try std.testing.expect(done);

    const resp = try parser.toResponse();

    try std.testing.expectEqual(@as(usize, 1), resp.content.len);
    try std.testing.expectEqual(types.ContentType.tool_use, resp.content[0].type);
    const tu = resp.content[0].tool_use.?;
    try std.testing.expectEqualStrings("call_abc", tu.id);
    try std.testing.expectEqualStrings("bash", tu.name);
    try std.testing.expectEqual(types.StopReason.tool_use, resp.stop_reason);
}
