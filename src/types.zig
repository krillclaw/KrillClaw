const std = @import("std");

// --- Providers ---

pub const Provider = enum {
    claude,
    openai,
    ollama,

    pub fn baseUrl(self: Provider) []const u8 {
        return switch (self) {
            .claude => "https://api.anthropic.com",
            .openai => "https://api.openai.com",
            .ollama => "http://localhost:11434",
        };
    }

    pub fn messagesPath(self: Provider) []const u8 {
        return switch (self) {
            .claude => "/v1/messages",
            .openai => "/v1/chat/completions",
            .ollama => "/api/chat",
        };
    }
};

// --- Transport ---

pub const TransportKind = enum {
    http,
    ble,
    serial,
};

// --- Message Types ---

pub const Role = enum {
    user,
    assistant,
    system,

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .user => "user",
            .assistant => "assistant",
            .system => "system",
        };
    }
};

pub const ContentType = enum {
    text,
    tool_use,
    tool_result,
};

pub const ToolUse = struct {
    id: []const u8,
    name: []const u8,
    input_raw: []const u8, // raw JSON of the input object
};

pub const ContentBlock = struct {
    type: ContentType,
    text: ?[]const u8 = null,
    tool_use: ?ToolUse = null,
    tool_use_id: ?[]const u8 = null,
    content: ?[]const u8 = null,
    is_error: bool = false,
};

pub const Message = struct {
    role: Role,
    content: []ContentBlock,
    token_estimate: u32 = 0,
};

pub const StopReason = enum {
    end_turn,
    tool_use,
    max_tokens,
    unknown,
};

pub const ApiResponse = struct {
    id: []const u8,
    stop_reason: StopReason,
    content: []ContentBlock,
    input_tokens: u32,
    output_tokens: u32,
};

// --- Streaming Event Types ---

pub const StreamEventType = enum {
    message_start,
    content_block_start,
    content_block_delta,
    content_block_stop,
    message_delta,
    message_stop,
    ping,
    error,
};

pub const StreamEvent = struct {
    type: StreamEventType,
    // For content_block_delta
    text_delta: ?[]const u8 = null,
    // For content_block_start (tool_use)
    tool_use: ?ToolUse = null,
    // For message_delta
    stop_reason: ?StopReason = null,
    // For message_start
    input_tokens: u32 = 0,
    output_tokens: u32 = 0,
    // Index of the content block
    index: u32 = 0,
};

// --- Tool Definitions ---

pub const ToolDef = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8,
};

pub const tools = [_]ToolDef{
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
};

// --- Config ---

pub const Config = struct {
    api_key: []const u8 = "",
    provider: Provider = .claude,
    model: []const u8 = "claude-sonnet-4-5-20250929",
    max_tokens: u32 = 8192,
    max_context_tokens: u32 = 100000,
    system_prompt: []const u8 =
        \\You are YoctoClaw, the world's smallest coding agent. You help users with software engineering tasks.
        \\You have tools: bash, read_file, write_file, edit_file, search, list_files.
        \\Be concise. Execute tools to get work done. Don't ask permission — just do it.
    ,
    max_turns: u32 = 50,
    streaming: bool = true,
    transport: TransportKind = .http,
    ble_device: ?[]const u8 = null,
    serial_port: ?[]const u8 = null,
    serial_baud: u32 = 115200,
    base_url: ?[]const u8 = null,
};
