const std = @import("std");
const types = @import("types.zig");
const tools_mod = @import("tools.zig");

/// Context window manager.
///
/// Estimates token usage and truncates old messages to stay within limits.
/// Uses a simple heuristic: ~4 characters per token (good enough for English).
pub const Context = struct {
    allocator: std.mem.Allocator,
    max_tokens: u32,
    /// Tokens reserved for the response
    reserve_tokens: u32 = 8192,
    /// Tokens used by system prompt + tool definitions (estimated once)
    system_tokens: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, config: types.Config) Context {
        // Estimate system prompt + tool defs
        var system_chars: usize = config.system_prompt.len;
        for (tools_mod.tool_definitions) |tool| {
            system_chars += tool.name.len + tool.description.len + tool.input_schema.len + 50;
        }

        return .{
            .allocator = allocator,
            .max_tokens = config.max_context_tokens,
            .reserve_tokens = config.max_tokens,
            .system_tokens = estimateTokens(system_chars),
        };
    }

    /// Estimate tokens for a message.
    pub fn estimateMessageTokens(msg: types.Message) u32 {
        var chars: usize = 10; // overhead for role, structure
        for (msg.content) |block| {
            switch (block.type) {
                .text => chars += (block.text orelse "").len,
                .tool_use => {
                    if (block.tool_use) |tu| {
                        chars += tu.name.len + tu.input_raw.len + 50;
                    }
                },
                .tool_result => {
                    chars += (block.content orelse "").len + 30;
                },
            }
        }
        return estimateTokens(chars);
    }

    /// Calculate total tokens used by all messages.
    pub fn totalTokens(self: *const Context, messages: []const types.Message) u32 {
        var total: u32 = self.system_tokens;
        for (messages) |msg| {
            total += estimateMessageTokens(msg);
        }
        return total;
    }

    /// Check if we're approaching the context limit.
    pub fn isNearLimit(self: *const Context, messages: []const types.Message) bool {
        const used = self.totalTokens(messages);
        return used + self.reserve_tokens > self.max_tokens;
    }

    /// Truncate old messages to fit within context window.
    /// Uses priority-based removal:
    ///   1. Remove assistant text messages first (lowest value)
    ///   2. Remove old user text messages next
    ///   3. Remove tool results last (highest value — small, high-info)
    /// Always keeps: first user message + last 4 messages.
    pub fn truncate(self: *Context, messages: *std.ArrayList(types.Message)) !void {
        if (!self.isNearLimit(messages.items)) return;

        const min_tail: usize = 4;
        var dropped: u32 = 0;

        // Pass 1: Remove assistant text-only messages (not recent)
        if (self.isNearLimit(messages.items)) {
            var i: usize = 1;
            while (i + min_tail < messages.items.len and self.isNearLimit(messages.items)) {
                if (messages.items[i].role == .assistant and !hasToolUse(messages.items[i])) {
                    _ = messages.orderedRemove(i);
                    dropped += 1;
                } else {
                    i += 1;
                }
            }
        }

        // Pass 2: Remove old user text-only messages (not tool results)
        if (self.isNearLimit(messages.items)) {
            var i: usize = 1;
            while (i + min_tail < messages.items.len and self.isNearLimit(messages.items)) {
                if (messages.items[i].role == .user and !hasToolResult(messages.items[i])) {
                    _ = messages.orderedRemove(i);
                    dropped += 1;
                } else {
                    i += 1;
                }
            }
        }

        // Pass 3: Remove remaining old messages (tool results, etc.)
        if (self.isNearLimit(messages.items)) {
            while (messages.items.len > min_tail + 1 and self.isNearLimit(messages.items)) {
                _ = messages.orderedRemove(1);
                dropped += 1;
            }
        }

        // If still over, replace first message with truncation notice
        if (self.isNearLimit(messages.items) and messages.items.len > 0) {
            const note = std.fmt.allocPrint(self.allocator,
                "[{d} earlier messages truncated to fit context window]", .{dropped}) catch
                "[Earlier conversation truncated]";
            const summary_block = try self.allocator.alloc(types.ContentBlock, 1);
            summary_block[0] = .{
                .type = .text,
                .text = note,
            };
            messages.items[0] = .{
                .role = .user,
                .content = summary_block,
                .token_estimate = 10,
            };
        }
    }

    fn hasToolUse(msg: types.Message) bool {
        for (msg.content) |block| {
            if (block.type == .tool_use) return true;
        }
        return false;
    }

    fn hasToolResult(msg: types.Message) bool {
        for (msg.content) |block| {
            if (block.type == .tool_result) return true;
        }
        return false;
    }

    /// Get a human-readable context usage string.
    pub fn usageString(self: *const Context, allocator: std.mem.Allocator, messages: []const types.Message) ![]const u8 {
        const used = self.totalTokens(messages);
        const pct = @as(u32, @intFromFloat(@as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(self.max_tokens)) * 100));
        return std.fmt.allocPrint(allocator, "{d}/{d}k tokens ({d}%)", .{
            used,
            self.max_tokens / 1000,
            pct,
        });
    }
};

/// Estimate tokens from character count (~4 chars per token for English).
fn estimateTokens(chars: usize) u32 {
    return @intCast(@max(1, chars / 4));
}

test "token estimation" {
    try std.testing.expectEqual(@as(u32, 25), estimateTokens(100));
    try std.testing.expectEqual(@as(u32, 1), estimateTokens(1));
    try std.testing.expectEqual(@as(u32, 1), estimateTokens(0));
}

test "estimateMessageTokens text" {
    var content = [_]types.ContentBlock{.{
        .type = .text,
        .text = "a" ** 400, // 400 chars ≈ 100 tokens
    }};
    const msg = types.Message{ .role = .user, .content = &content };
    const tokens = Context.estimateMessageTokens(msg);
    // ~400 chars / 4 + overhead ≈ 102
    try std.testing.expect(tokens >= 90);
    try std.testing.expect(tokens <= 120);
}

test "estimateMessageTokens tool_result" {
    var content = [_]types.ContentBlock{.{
        .type = .tool_result,
        .content = "some output",
        .tool_use_id = "toolu_123",
    }};
    const msg = types.Message{ .role = .user, .content = &content };
    const tokens = Context.estimateMessageTokens(msg);
    // Should include overhead
    try std.testing.expect(tokens > 1);
}

test "isNearLimit false" {
    const alloc = std.testing.allocator;
    const config = types.Config{ .max_context_tokens = 100000, .max_tokens = 8192 };
    const ctx = Context.init(alloc, config);

    var content = [_]types.ContentBlock{.{ .type = .text, .text = "short message" }};
    var msgs = [_]types.Message{.{ .role = .user, .content = &content }};
    try std.testing.expect(!ctx.isNearLimit(&msgs));
}

test "isNearLimit true" {
    const alloc = std.testing.allocator;
    // Set very small context to trigger limit
    const config = types.Config{ .max_context_tokens = 100, .max_tokens = 50 };
    const ctx = Context.init(alloc, config);

    var content = [_]types.ContentBlock{.{ .type = .text, .text = "a" ** 400 }};
    var msgs = [_]types.Message{.{ .role = .user, .content = &content }};
    try std.testing.expect(ctx.isNearLimit(&msgs));
}

test "usageString format" {
    const alloc = std.testing.allocator;
    const config = types.Config{ .max_context_tokens = 100000, .max_tokens = 8192 };
    const ctx = Context.init(alloc, config);

    var content = [_]types.ContentBlock{.{ .type = .text, .text = "hello" }};
    var msgs = [_]types.Message{.{ .role = .user, .content = &content }};

    const usage = try ctx.usageString(alloc, &msgs);
    defer alloc.free(usage);

    // Should contain "k tokens" and "%"
    try std.testing.expect(std.mem.indexOf(u8, usage, "k tokens") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage, "%") != null);
}
