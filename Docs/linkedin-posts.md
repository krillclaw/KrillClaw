# LinkedIn Launch Posts — YoctoClaw

## Version 1: Announcement

**We just open-sourced the world's smallest coding agent.**

YoctoClaw is a fully autonomous AI coding agent written in ~3,500 lines of Zig. The binary is 180KB — smaller than most JPEGs.

It does what Claude Code does: bash, read files, write files, edit files, search, list. It connects to Claude, OpenAI, or Ollama. It loops until the task is done.

The difference? Claude Code is ~50MB with 500 npm dependencies. YoctoClaw is 180KB with zero dependencies.

Same agent loop. 1000x smaller.

We built three compile-time profiles (coding, IoT, robotics) with BLE and serial transports, so it can run on a $3 ESP32 or an nRF5340 dev kit. The agent brain lives on the device. Your phone bridges it to the cloud.

Why does this matter? Because the "agent harness" — the code that orchestrates LLM calls — is simpler than you think. The complexity in existing agents isn't the harness. It's the platform around it.

MIT licensed. 16 Zig source files. You can read the entire codebase in an hour.

→ https://github.com/yoctoclaw/TinyDancer

#AI #CodingAgent #Zig #OpenSource #Embedded

---

## Version 2: Technical Deep-Dive

**I hand-rolled a JSON parser in 500 lines of Zig. Here's why.**

When you're building a coding agent that needs to fit in 180KB, every dependency matters. Zig's std.json works — but we only need to extract specific keys from API responses and build request bodies. A custom parser/builder handles both in 500 lines with zero allocations.

This is the philosophy behind YoctoClaw: every line earns its place.

The architecture:
• agent.zig (250 lines) — the core loop with FNV-1a stuck-loop detection
• api.zig (329 lines) — multi-provider HTTP client for Claude, OpenAI, Ollama
• stream.zig (344 lines) — SSE streaming parser with safe string ownership
• tools_coding.zig (280 lines) — 7 coding tools with injection-safe file operations
• tools_iot.zig (95 lines) — 6 IoT bridge tools with rate limiting
• tools_robotics.zig (155 lines) — 3 robot control tools with safety bounds
• json.zig (500 lines) — hand-rolled JSON, no dependencies

16 files. ~3,500 lines total (core + tests). 39 unit tests. CI with a binary size gate (<300KB).

The transport layer uses vtables — the same binary works over HTTP (desktop), BLE (smart ring), or serial (dev board). Feature flags keep unused transports out of the binary.

For embedded targets, we built a fixed arena allocator with preset sizes (4KB–256KB). No OS heap required. Reset between agent turns. Fits on an nRF5340 with 512KB RAM.

We added compile-time profiles that swap entire tool sets: coding (7 tools), IoT (6 MQTT/HTTP tools), robotics (3 safety-bounded control tools). Only the selected profile compiles — zero runtime overhead.

No garbage collector. No runtime. Compiles in ~1 second.

→ https://github.com/yoctoclaw/TinyDancer

#Zig #SystemsProgramming #AI #Embedded

---

## Version 3: Why Zig?

**Why we chose Zig for the world's smallest coding agent.**

We needed a language that compiles to native code with no runtime, gives us control over every allocation, cross-compiles to embedded targets, and produces the smallest possible binary.

Rust was the obvious choice. ZeroClaw proved it works — 3.4MB, ~3K LOC. But Zig gave us something Rust couldn't: a 180KB binary with zero ceremony.

No borrow checker battles. No proc macros. No Cargo.toml with 50 transitive deps. Just `zig build` and a 180KB static binary.

Zig's comptime is remarkable. We use it for compile-time feature flags (BLE, serial, embedded allocator) that strip unused code paths entirely. The result: one codebase, multiple targets, minimal binary.

The standard library is practical without being bloated. `std.http.Client` handles HTTPS. `std.fs` handles file operations. `std.mem` handles parsing. We didn't need anything else.

Compile time: ~1 second. Binary size: ~180KB (ReleaseSmall). RAM usage: ~2MB.

For comparison:
• Go (YoctoClaw Go): 8MB binary, Go GC overhead, no embedded target
• Rust (ZeroClaw): 3.4MB binary, excellent but 19x larger
• TypeScript (Claude Code): 50MB, 500 deps, 200MB RAM

Zig hit the sweet spot: systems-level control with modern ergonomics.

If you're building performance-critical tools and haven't tried Zig — start here. You can read our entire ~3,500-line codebase in an afternoon.

→ https://github.com/yoctoclaw/TinyDancer

#Zig #ProgrammingLanguages #SystemsProgramming #AI
