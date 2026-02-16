//! ReAct (Reason + Act) agent loop — thin orchestration layer.
//!
//! Implements the think → act → observe cycle with a hard iteration cap.
//! Zero heap allocation in the orchestration logic itself — all allocation
//! is done by the caller-provided allocator for message/result storage.

const std = @import("std");
const types = @import("types.zig");
const json = @import("json.zig");
const tool_exec = @import("tools.zig");

/// Maximum ReAct iterations before forced termination.
pub const MAX_ITERATIONS: u32 = 10;

/// Result of a single ReAct iteration.
pub const StepResult = enum {
    /// LLM produced tool calls — continue with observations.
    needs_observation,
    /// LLM produced a final answer — stop.
    done,
    /// Hit max tokens — stop.
    max_tokens,
};

/// Classify an API response into a ReAct step result.
pub fn classify(response: types.ApiResponse) StepResult {
    if (response.stop_reason == .max_tokens) return .max_tokens;
    for (response.content) |block| {
        if (block.type == .tool_use) return .needs_observation;
    }
    return .done;
}

/// Extract "thought" text from content blocks (text blocks before any tool_use).
/// Returns null if no thought text found. Does not allocate.
pub fn extractThought(content: []const types.ContentBlock) ?[]const u8 {
    for (content) |block| {
        if (block.type == .tool_use) break;
        if (block.type == .text) {
            if (block.text) |t| {
                if (t.len > 0) return t;
            }
        }
    }
    return null;
}

/// Execute all tool_use blocks in a response, returning tool_result ContentBlocks.
/// Uses the provided allocator for result storage.
/// loop_hashes is a ring buffer for detecting repeated calls; returns error text
/// for calls seen 3+ times.
pub fn executeTools(
    allocator: std.mem.Allocator,
    content: []const types.ContentBlock,
    loop_hashes: *[8][2]u64,
    loop_idx: *usize,
) ![]types.ContentBlock {
    var results: std.ArrayList(types.ContentBlock) = .{};
    for (content) |block| {
        if (block.type != .tool_use) continue;
        const tu = block.tool_use orelse continue;

        // Loop detection
        const h = hashCall(tu.name, tu.input_raw);
        var repeats: u32 = 0;
        for (loop_hashes) |entry| {
            if (entry[0] == h[0] and entry[1] == h[1]) repeats += 1;
        }
        loop_hashes[loop_idx.* % 8] = h;
        loop_idx.* += 1;

        if (repeats >= 2) {
            try results.append(allocator, .{
                .type = .tool_result,
                .tool_use_id = tu.id,
                .content = "ERROR: Repeated identical tool call. Try a different approach.",
                .is_error = true,
            });
            continue;
        }

        const result = tool_exec.execute(allocator, tu);
        try results.append(allocator, .{
            .type = .tool_result,
            .tool_use_id = tu.id,
            .content = result.output,
            .is_error = result.is_error,
        });
    }
    return try results.toOwnedSlice(allocator);
}

fn hashCall(name: []const u8, input: []const u8) [2]u64 {
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
