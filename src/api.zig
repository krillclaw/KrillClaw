const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");
const StreamParser = @import("stream.zig").StreamParser;

const CLAUDE_API_VERSION = "2023-06-01";

pub const ApiError = error{
    HttpError,
    InvalidResponse,
    RateLimited,
    ServerError,
    AuthError,
    OutOfMemory,
    ParseError,
    ConnectionRefused,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    config: types.Config,
    http_client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, config: types.Config) Client {
        return .{
            .allocator = allocator,
            .config = config,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *Client) void {
        self.http_client.deinit();
    }

    /// Send messages and return parsed response (non-streaming).
    pub fn sendMessages(self: *Client, messages: []const types.Message) !types.ApiResponse {
        var cfg = self.config;
        cfg.streaming = false;
        return self.doRequest(cfg, messages, null);
    }

    /// Send messages with streaming. Calls on_text for each text chunk.
    pub fn sendMessagesStreaming(
        self: *Client,
        messages: []const types.Message,
        on_text: ?*const fn ([]const u8) void,
    ) !types.ApiResponse {
        var cfg = self.config;
        cfg.streaming = true;
        return self.doRequest(cfg, messages, on_text);
    }

    fn doRequest(
        self: *Client,
        config: types.Config,
        messages: []const types.Message,
        on_text: ?*const fn ([]const u8) void,
    ) !types.ApiResponse {
        // Build request body based on provider
        const body = switch (config.provider) {
            .claude => try json.buildClaudeRequest(self.allocator, config, messages),
            .openai, .ollama => try json.buildOpenAiRequest(self.allocator, config, messages),
        };
        defer self.allocator.free(body);

        // Determine URL
        const base = config.base_url orelse config.provider.baseUrl();
        const path = config.provider.messagesPath();
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ base, path });
        defer self.allocator.free(url);

        // Build headers based on provider
        var auth_buf: [512]u8 = undefined;

        const extra_headers: []const std.http.Header = switch (config.provider) {
            .claude => &.{
                .{ .name = "x-api-key", .value = config.api_key },
                .{ .name = "anthropic-version", .value = CLAUDE_API_VERSION },
                .{ .name = "content-type", .value = "application/json" },
            },
            .openai => blk: {
                const auth = std.fmt.bufPrint(&auth_buf, "Bearer {s}", .{config.api_key}) catch return ApiError.OutOfMemory;
                break :blk &.{
                    .{ .name = "Authorization", .value = auth },
                    .{ .name = "content-type", .value = "application/json" },
                };
            },
            .ollama => &.{
                .{ .name = "content-type", .value = "application/json" },
            },
        };

        const uri = std.Uri.parse(url) catch return ApiError.HttpError;

        // Use request() for both streaming and non-streaming
        var req = self.http_client.request(.POST, uri, .{
            .extra_headers = extra_headers,
        }) catch return ApiError.ConnectionRefused;
        defer req.deinit();

        // Send body
        req.transfer_encoding = .{ .content_length = body.len };
        var send_body = req.sendBodyUnflushed(&.{}) catch return ApiError.HttpError;
        send_body.writer.writeAll(body) catch return ApiError.HttpError;
        send_body.end() catch return ApiError.HttpError;
        req.connection.?.flush() catch return ApiError.HttpError;

        // Receive response head
        var head_buf: [16384]u8 = undefined;
        var response = req.receiveHead(&head_buf) catch return ApiError.HttpError;

        if (response.head.status != .ok) {
            return switch (response.head.status) {
                .too_many_requests => ApiError.RateLimited,
                .unauthorized => ApiError.AuthError,
                .internal_server_error, .bad_gateway, .service_unavailable => ApiError.ServerError,
                else => ApiError.HttpError,
            };
        }

        // Read response body
        var transfer_buf: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buf);

        if (config.streaming) {
            return self.readStreaming(reader, on_text);
        }

        // Non-streaming: read all
        var resp_body_list: std.ArrayList(u8) = .{};
        defer resp_body_list.deinit(self.allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const n = reader.readSliceShort(&read_buf) catch return ApiError.HttpError;
            if (n == 0) break;
            resp_body_list.appendSlice(self.allocator, read_buf[0..n]) catch return ApiError.OutOfMemory;
        }

        return parseResponse(self.allocator, resp_body_list.items, config.provider);
    }

    fn readStreaming(self: *Client, reader: anytype, on_text: ?*const fn ([]const u8) void) !types.ApiResponse {
        var parser = StreamParser.init(self.allocator);
        defer parser.deinit();

        var buf: [4096]u8 = undefined;
        while (true) {
            const n = reader.readSliceShort(&buf) catch return ApiError.HttpError;
            if (n == 0) break;

            const done = try parser.feed(buf[0..n], on_text);
            if (done) break;
        }

        return parser.toResponse();
    }
};

/// Parse a non-streaming Claude API response.
fn parseResponse(allocator: std.mem.Allocator, body: []const u8, provider: types.Provider) !types.ApiResponse {
    return switch (provider) {
        .claude => parseClaudeResponse(allocator, body),
        .openai, .ollama => parseOpenAiResponse(allocator, body),
    };
}

fn parseClaudeResponse(allocator: std.mem.Allocator, body: []const u8) !types.ApiResponse {
    const id = json.extractString(body, "id") orelse return ApiError.InvalidResponse;
    const stop_str = json.extractString(body, "stop_reason") orelse "unknown";

    const stop_reason = parseStopReason(stop_str);

    const usage_json = json.extractObject(body, "usage") orelse "{}";
    const input_tokens = json.extractInt(usage_json, "input_tokens") orelse 0;
    const output_tokens = json.extractInt(usage_json, "output_tokens") orelse 0;

    const content_json = json.extractArray(body, "content") orelse return ApiError.InvalidResponse;
    const blocks = try parseContentBlocks(allocator, content_json);

    return .{
        .id = try allocator.dupe(u8, id),
        .stop_reason = stop_reason,
        .content = blocks,
        .input_tokens = input_tokens,
        .output_tokens = output_tokens,
    };
}

fn parseOpenAiResponse(allocator: std.mem.Allocator, body: []const u8) !types.ApiResponse {
    const id = json.extractString(body, "id") orelse "";
    const choices = json.extractArray(body, "choices") orelse return ApiError.InvalidResponse;

    // Parse first choice
    const finish = json.extractString(choices, "finish_reason") orelse "stop";
    const stop_reason: types.StopReason = if (std.mem.eql(u8, finish, "stop"))
        .end_turn
    else if (std.mem.eql(u8, finish, "tool_calls"))
        .tool_use
    else if (std.mem.eql(u8, finish, "length"))
        .max_tokens
    else
        .unknown;

    const message = json.extractObject(choices, "message") orelse return ApiError.InvalidResponse;

    var blocks: std.ArrayList(types.ContentBlock) = .{};

    // Extract text content
    if (json.extractString(message, "content")) |text| {
        if (text.len > 0) {
            try blocks.append(allocator, .{
                .type = .text,
                .text = try allocator.dupe(u8, text),
            });
        }
    }

    // Extract tool calls
    if (json.extractArray(message, "tool_calls")) |tool_calls_json| {
        try parseOpenAiToolCalls(allocator, tool_calls_json, &blocks);
    }

    // Usage
    const usage = json.extractObject(body, "usage") orelse "{}";

    return .{
        .id = try allocator.dupe(u8, id),
        .stop_reason = stop_reason,
        .content = try blocks.toOwnedSlice(allocator),
        .input_tokens = json.extractInt(usage, "prompt_tokens") orelse 0,
        .output_tokens = json.extractInt(usage, "completion_tokens") orelse 0,
    };
}

fn parseOpenAiToolCalls(allocator: std.mem.Allocator, tool_calls_json: []const u8, blocks: *std.ArrayList(types.ContentBlock)) !void {
    // Walk through array finding objects
    var pos: usize = 0;
    while (pos < tool_calls_json.len) : (pos += 1) {
        if (tool_calls_json[pos] != '{') continue;

        var depth: u32 = 0;
        var in_string = false;
        var end = pos;
        while (end < tool_calls_json.len) : (end += 1) {
            if (tool_calls_json[end] == '\\' and in_string) {
                end += 1;
                continue;
            }
            if (tool_calls_json[end] == '"') in_string = !in_string;
            if (!in_string) {
                if (tool_calls_json[end] == '{') depth += 1;
                if (tool_calls_json[end] == '}') {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
        }

        const obj = tool_calls_json[pos .. end + 1];
        const tc_id = json.extractString(obj, "id") orelse "";
        const func = json.extractObject(obj, "function") orelse {
            pos = end;
            continue;
        };
        const name = json.extractString(func, "name") orelse "";
        const arguments = json.extractString(func, "arguments") orelse "{}";

        try blocks.append(allocator, .{
            .type = .tool_use,
            .tool_use = .{
                .id = try allocator.dupe(u8, tc_id),
                .name = try allocator.dupe(u8, name),
                .input_raw = try allocator.dupe(u8, arguments),
            },
        });

        pos = end;
    }
}

fn parseContentBlocks(allocator: std.mem.Allocator, content_json: []const u8) ![]types.ContentBlock {
    var blocks: std.ArrayList(types.ContentBlock) = .{};

    var pos: usize = 0;
    while (pos < content_json.len) : (pos += 1) {
        if (content_json[pos] != '{') continue;

        var depth: u32 = 0;
        var in_string = false;
        var end = pos;
        while (end < content_json.len) : (end += 1) {
            if (content_json[end] == '\\' and in_string) {
                end += 1;
                continue;
            }
            if (content_json[end] == '"') in_string = !in_string;
            if (!in_string) {
                if (content_json[end] == '{') depth += 1;
                if (content_json[end] == '}') {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
        }

        const obj = content_json[pos .. end + 1];
        const block_type = json.extractString(obj, "type") orelse {
            pos = end;
            continue;
        };

        if (std.mem.eql(u8, block_type, "text")) {
            try blocks.append(allocator, .{
                .type = .text,
                .text = try allocator.dupe(u8, json.extractString(obj, "text") orelse ""),
            });
        } else if (std.mem.eql(u8, block_type, "tool_use")) {
            try blocks.append(allocator, .{
                .type = .tool_use,
                .tool_use = .{
                    .id = try allocator.dupe(u8, json.extractString(obj, "id") orelse ""),
                    .name = try allocator.dupe(u8, json.extractString(obj, "name") orelse ""),
                    .input_raw = try allocator.dupe(u8, json.extractObject(obj, "input") orelse "{}"),
                },
            });
        }

        pos = end;
    }

    return blocks.toOwnedSlice(allocator);
}

fn parseStopReason(s: []const u8) types.StopReason {
    if (std.mem.eql(u8, s, "end_turn")) return .end_turn;
    if (std.mem.eql(u8, s, "tool_use")) return .tool_use;
    if (std.mem.eql(u8, s, "max_tokens")) return .max_tokens;
    return .unknown;
}
