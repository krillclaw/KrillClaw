const std = @import("std");
const types = @import("types.zig");
const api = @import("api.zig");
const tool_exec = @import("tools.zig");
const json = @import("json.zig");
const Context = @import("context.zig").Context;

const Color = struct {
    const reset = "\x1b[0m";
    const cyan = "\x1b[36m";
    const yellow = "\x1b[33m";
    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const dim = "\x1b[2m";
    const bold = "\x1b[1m";
    const magenta = "\x1b[35m";
};

pub const Agent = struct {
    allocator: std.mem.Allocator,
    client: api.Client,
    config: types.Config,
    messages: std.ArrayList(types.Message),
    context: Context,
    total_input_tokens: u64,
    total_output_tokens: u64,
    stdout: std.fs.File.Writer,
    // Loop detection: track recent tool calls to detect stuck loops
    recent_tool_calls: [8][2]u64 = .{
        .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 },
        .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 },
    },
    recent_tool_idx: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: types.Config) Agent {
        return .{
            .allocator = allocator,
            .client = api.Client.init(allocator, config),
            .config = config,
            .messages = std.ArrayList(types.Message).init(allocator),
            .context = Context.init(allocator, config),
            .total_input_tokens = 0,
            .total_output_tokens = 0,
            .stdout = std.io.getStdOut().writer(),
        };
    }

    pub fn deinit(self: *Agent) void {
        self.client.deinit();
        self.messages.deinit();
    }

    /// Run the agent with a user prompt.
    pub fn run(self: *Agent, prompt: []const u8) !void {
        // Add user message
        const user_content = try self.allocator.alloc(types.ContentBlock, 1);
        user_content[0] = .{
            .type = .text,
            .text = try self.allocator.dupe(u8, prompt),
        };
        try self.messages.append(.{
            .role = .user,
            .content = user_content,
        });

        var turn: u32 = 0;
        while (turn < self.config.max_turns) : (turn += 1) {
            // Context window management
            try self.context.truncate(&self.messages);

            // Show thinking indicator
            try self.stdout.print("\n{s}[yoctoclaw]{s} ", .{ Color.cyan, Color.reset });

            // Call API (streaming or non-streaming)
            const response = if (self.config.streaming)
                self.client.sendMessagesStreaming(self.messages.items, &printTextDelta) catch |err| {
                    return self.handleApiError(err);
                }
            else
                self.client.sendMessages(self.messages.items) catch |err| {
                    return self.handleApiError(err);
                };

            self.total_input_tokens += response.input_tokens;
            self.total_output_tokens += response.output_tokens;

            // Add assistant message
            try self.messages.append(.{
                .role = .assistant,
                .content = response.content,
            });

            // Process content blocks
            var has_tool_use = false;
            var tool_results = std.ArrayList(types.ContentBlock).init(self.allocator);
            defer tool_results.deinit();

            for (response.content) |block| {
                switch (block.type) {
                    .text => {
                        // If not streaming, print text now
                        if (!self.config.streaming) {
                            try self.stdout.print("{s}", .{block.text orelse ""});
                        }
                    },
                    .tool_use => {
                        has_tool_use = true;
                        const tu = block.tool_use orelse continue;

                        try self.stdout.print("\n{s}[tool]{s} {s}{s}{s}", .{
                            Color.yellow, Color.reset,
                            Color.bold,   tu.name,
                            Color.reset,
                        });

                        // Show tool-specific info
                        if (std.mem.eql(u8, tu.name, "bash")) {
                            if (json.extractString(tu.input_raw, "command")) |c| {
                                try self.stdout.print(" {s}{s}{s}", .{ Color.dim, c, Color.reset });
                            }
                        } else if (std.mem.eql(u8, tu.name, "read_file") or
                            std.mem.eql(u8, tu.name, "write_file") or
                            std.mem.eql(u8, tu.name, "edit_file"))
                        {
                            if (json.extractString(tu.input_raw, "path")) |p| {
                                try self.stdout.print(" {s}{s}{s}", .{ Color.dim, p, Color.reset });
                            }
                        } else if (std.mem.eql(u8, tu.name, "search")) {
                            if (json.extractString(tu.input_raw, "pattern")) |p| {
                                try self.stdout.print(" {s}/{s}/{s}", .{ Color.dim, p, Color.reset });
                            }
                        }
                        try self.stdout.print("\n", .{});

                        // Loop detection: hash (name, input) and check for repeats
                        const call_hash = hashToolCall(tu.name, tu.input_raw);
                        var repeat_count: u32 = 0;
                        for (self.recent_tool_calls) |entry| {
                            if (entry[0] == call_hash[0] and entry[1] == call_hash[1]) {
                                repeat_count += 1;
                            }
                        }
                        self.recent_tool_calls[self.recent_tool_idx % 8] = call_hash;
                        self.recent_tool_idx += 1;

                        // If stuck (same call 3+ times), warn the LLM
                        if (repeat_count >= 2) {
                            try self.stdout.print("{s}(loop detected: same tool call {d}x){s}\n", .{
                                Color.yellow, repeat_count + 1, Color.reset,
                            });
                            try tool_results.append(.{
                                .type = .tool_result,
                                .tool_use_id = tu.id,
                                .content = "ERROR: You have called this tool with identical input multiple times. The result will be the same. Try a different approach or different parameters.",
                                .is_error = true,
                            });
                            continue;
                        }

                        // Execute
                        const result = tool_exec.execute(self.allocator, tu);

                        // Print truncated output
                        const display = if (result.output.len > 500) result.output[0..500] else result.output;
                        if (result.is_error) {
                            try self.stdout.print("{s}{s}{s}\n", .{ Color.red, display, Color.reset });
                        } else {
                            try self.stdout.print("{s}{s}{s}\n", .{ Color.dim, display, Color.reset });
                        }
                        if (result.output.len > 500) {
                            try self.stdout.print("{s}... ({d} bytes total){s}\n", .{ Color.dim, result.output.len, Color.reset });
                        }

                        try tool_results.append(.{
                            .type = .tool_result,
                            .tool_use_id = tu.id,
                            .content = result.output,
                            .is_error = result.is_error,
                        });
                    },
                    .tool_result => {},
                }
            }

            // If tool uses, add results and continue loop
            if (has_tool_use) {
                try self.messages.append(.{
                    .role = .user,
                    .content = try tool_results.toOwnedSlice(),
                });
                continue;
            }

            // Done
            if (response.stop_reason == .end_turn) {
                try self.stdout.print("\n", .{});
                break;
            }
            if (response.stop_reason == .max_tokens) {
                try self.stdout.print("\n{s}(max tokens){s}\n", .{ Color.yellow, Color.reset });
                break;
            }
        }

        if (turn >= self.config.max_turns) {
            try self.stdout.print("\n{s}(max turns: {d}){s}\n", .{ Color.yellow, self.config.max_turns, Color.reset });
        }

        // Usage summary
        const ctx_usage = self.context.usageString(self.allocator, self.messages.items) catch "?";
        try self.stdout.print("{s}[tokens] in:{d} out:{d} | ctx:{s}{s}\n", .{
            Color.dim,
            self.total_input_tokens,
            self.total_output_tokens,
            ctx_usage,
            Color.reset,
        });
    }

    fn handleApiError(self: *Agent, err: anyerror) !void {
        try self.stdout.print("{s}API error: {}{s}\n", .{ Color.red, err, Color.reset });
        if (err == api.ApiError.RateLimited) {
            try self.stdout.print("{s}Rate limited. Wait and retry.{s}\n", .{ Color.yellow, Color.reset });
        } else if (err == api.ApiError.AuthError) {
            try self.stdout.print("{s}Check your API key.{s}\n", .{ Color.yellow, Color.reset });
        } else if (err == api.ApiError.ConnectionRefused) {
            try self.stdout.print("{s}Cannot connect. Check base URL and network.{s}\n", .{ Color.yellow, Color.reset });
        }
        return err;
    }
};

/// Simple FNV-1a hash of tool name + input for loop detection.
fn hashToolCall(name: []const u8, input: []const u8) [2]u64 {
    return .{ fnv1a(name), fnv1a(input) };
}

fn fnv1a(data: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (data) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

/// Streaming text callback — prints text deltas as they arrive.
fn printTextDelta(text: []const u8) void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(text) catch {};
}
