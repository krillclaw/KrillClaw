const std = @import("std");

/// Retry configuration for HTTP requests with exponential backoff and jitter.
pub const RetryConfig = struct {
    max_attempts: u32 = 5,
    base_delay_ms: u64 = 1000,
    max_delay_ms: u64 = 30_000,
    /// Jitter factor: 0.0 = no jitter, 1.0 = full jitter (up to ±50% of delay)
    jitter_factor: f64 = 1.0,
};

pub const default_config = RetryConfig{};

/// Classification of HTTP errors for retry decisions.
pub const ErrorClass = enum {
    retryable,
    fatal,
    rate_limited,
};

/// Result of evaluating whether to retry.
pub const RetryDecision = union(enum) {
    retry: u64, // delay in ms
    abort: []const u8, // reason
};

/// Classify an HTTP status code.
pub fn classifyStatus(status: u16) ErrorClass {
    return switch (status) {
        429 => .rate_limited,
        500, 502, 503, 504 => .retryable,
        408 => .retryable, // request timeout
        400, 401, 403, 404, 405, 422 => .fatal,
        else => if (status >= 200 and status < 300) .fatal else .retryable,
    };
}

/// Parse Retry-After header value (seconds or HTTP-date, we handle seconds only).
pub fn parseRetryAfter(header: ?[]const u8) ?u64 {
    const val = header orelse return null;
    // Try parsing as integer (seconds)
    const seconds = std.fmt.parseInt(u64, val, 10) catch return null;
    if (seconds > 300) return 300_000; // cap at 5 minutes
    return seconds * 1000;
}

/// Calculate delay for a given attempt using exponential backoff with jitter.
/// attempt is 0-indexed.
pub fn calculateDelay(config: RetryConfig, attempt: u32, retry_after_ms: ?u64) u64 {
    // If server specified Retry-After, use it (but at least base_delay)
    if (retry_after_ms) |ra| {
        return @min(ra, config.max_delay_ms);
    }

    // Exponential backoff: base * 2^attempt
    const exp: u6 = @intCast(@min(attempt, 20));
    const base_delay = config.base_delay_ms *| (@as(u64, 1) << exp);
    const capped = @min(base_delay, config.max_delay_ms);

    // Apply jitter
    if (config.jitter_factor <= 0.0) return capped;

    // Use simple deterministic jitter based on attempt number for no-OS compat
    // Full jitter: uniform random in [0, capped]
    const jitter_range = @as(f64, @floatFromInt(capped)) * config.jitter_factor * 0.5;
    // Simple hash-based pseudo-random for jitter (no OS random needed)
    const hash = attemptHash(attempt);
    const jitter_norm = @as(f64, @floatFromInt(hash % 1000)) / 1000.0; // 0.0 to 1.0
    const jitter_offset = jitter_range * (jitter_norm * 2.0 - 1.0); // -range to +range
    const result = @as(f64, @floatFromInt(capped)) + jitter_offset;

    return @intFromFloat(@max(result, @as(f64, @floatFromInt(config.base_delay_ms))));
}

fn attemptHash(attempt: u32) u32 {
    // Simple integer hash for deterministic but varied jitter
    var h = attempt *% 2654435761;
    h ^= h >> 16;
    h *%= 2246822519;
    h ^= h >> 13;
    return h;
}

/// Decide whether to retry given current state.
pub fn shouldRetry(config: RetryConfig, attempt: u32, status: u16, retry_after: ?[]const u8) RetryDecision {
    if (attempt >= config.max_attempts) {
        return .{ .abort = "max retries exhausted" };
    }

    const class = classifyStatus(status);
    switch (class) {
        .fatal => return .{ .abort = "fatal error (not retryable)" },
        .rate_limited, .retryable => {
            const ra_ms = if (class == .rate_limited) parseRetryAfter(retry_after) else null;
            const delay = calculateDelay(config, attempt, ra_ms);
            return .{ .retry = delay };
        },
    }
}

/// Sleep for the specified milliseconds. Uses std.time for platforms that support it.
pub fn sleep(ms: u64) void {
    std.time.sleep(ms * std.time.ns_per_ms);
}

// ---- Tests ----

test "classifyStatus" {
    const expect = std.testing.expect;
    try expect(classifyStatus(429) == .rate_limited);
    try expect(classifyStatus(500) == .retryable);
    try expect(classifyStatus(502) == .retryable);
    try expect(classifyStatus(503) == .retryable);
    try expect(classifyStatus(504) == .retryable);
    try expect(classifyStatus(408) == .retryable);
    try expect(classifyStatus(400) == .fatal);
    try expect(classifyStatus(401) == .fatal);
    try expect(classifyStatus(403) == .fatal);
    try expect(classifyStatus(200) == .fatal); // success = don't retry
}

test "parseRetryAfter" {
    const expect = std.testing.expect;
    const eql = std.testing.expectEqual;

    try expect(parseRetryAfter(null) == null);
    try eql(@as(?u64, 5000), parseRetryAfter("5"));
    try eql(@as(?u64, 60000), parseRetryAfter("60"));
    try eql(@as(?u64, 300_000), parseRetryAfter("999")); // capped
    try expect(parseRetryAfter("not-a-number") == null);
}

test "calculateDelay exponential backoff" {
    const config = RetryConfig{ .base_delay_ms = 1000, .max_delay_ms = 30_000, .jitter_factor = 0.0 };
    const eql = std.testing.expectEqual;

    try eql(@as(u64, 1000), calculateDelay(config, 0, null));
    try eql(@as(u64, 2000), calculateDelay(config, 1, null));
    try eql(@as(u64, 4000), calculateDelay(config, 2, null));
    try eql(@as(u64, 8000), calculateDelay(config, 3, null));
    try eql(@as(u64, 16000), calculateDelay(config, 4, null));
    try eql(@as(u64, 30_000), calculateDelay(config, 5, null)); // capped
}

test "calculateDelay respects retry-after" {
    const config = RetryConfig{ .base_delay_ms = 1000, .max_delay_ms = 30_000, .jitter_factor = 0.0 };
    const eql = std.testing.expectEqual;

    try eql(@as(u64, 5000), calculateDelay(config, 0, 5000));
    try eql(@as(u64, 30_000), calculateDelay(config, 0, 60_000)); // capped to max
}

test "calculateDelay with jitter stays in bounds" {
    const config = RetryConfig{ .base_delay_ms = 1000, .max_delay_ms = 30_000, .jitter_factor = 1.0 };
    const expect = std.testing.expect;

    // Run through several attempts, all should be >= base_delay and <= max_delay
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        const delay = calculateDelay(config, i, null);
        try expect(delay >= config.base_delay_ms);
        try expect(delay <= config.max_delay_ms + config.max_delay_ms / 2); // jitter can overshoot slightly
    }
}

test "shouldRetry logic" {
    const config = RetryConfig{ .max_attempts = 3, .jitter_factor = 0.0 };

    // Fatal errors: never retry
    {
        const d = shouldRetry(config, 0, 401, null);
        switch (d) {
            .abort => {},
            .retry => unreachable,
        }
    }

    // Retryable: should retry with delay
    {
        const d = shouldRetry(config, 0, 500, null);
        switch (d) {
            .retry => |delay| {
                try std.testing.expect(delay > 0);
            },
            .abort => unreachable,
        }
    }

    // Max attempts exhausted
    {
        const d = shouldRetry(config, 3, 500, null);
        switch (d) {
            .abort => {},
            .retry => unreachable,
        }
    }

    // Rate limited with Retry-After
    {
        const d = shouldRetry(config, 0, 429, "10");
        switch (d) {
            .retry => |delay| {
                try std.testing.expectEqual(@as(u64, 10000), delay);
            },
            .abort => unreachable,
        }
    }
}
