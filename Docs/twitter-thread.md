# Twitter/X Launch Thread — YoctoClaw

## Thread (10 tweets)

### 1/10 — The Hook
We built a full coding agent in ~3,500 lines of Zig.

The binary is 180KB. Smaller than most JPEGs.

It connects to Claude, OpenAI, or Ollama. Has 7 coding tools. Loops until done.

Zero dependencies. Zero runtime. Zero GC.

Here's the source: github.com/yoctoclaw/TinyDancer 🧵

### 2/10 — The Comparison
How YoctoClaw compares to existing agents:

YoctoClaw: 180KB, 2MB RAM, 0 deps
Claude Code: 50MB, 200MB RAM, 500 deps
Cursor: 500MB, 1GB RAM, 1000+ deps
Aider: 50MB, 150MB RAM, 100 deps

Same core job. 1000x less.

### 3/10 — What It Does
YoctoClaw coding profile has 7 tools:
• bash — run any shell command
• read_file
• write_file
• edit_file — find-and-replace
• search — substring across files
• list_files — with glob filter
• apply_patch — unified diff format

SSE streaming. Context window management. Stuck-loop detection.

It's a real agent, not a wrapper.

### 4/10 — Three Providers
One binary, three providers:

./yoctoclaw "fix the tests"                    # Claude
./yoctoclaw --provider openai "fix the tests"  # OpenAI
./yoctoclaw --provider ollama "fix the tests"  # Ollama (local)

Switch with a flag. No lock-in.

### 5/10 — The Architecture
16 files. That's it.

agent.zig — core loop (250 lines)
api.zig — multi-provider HTTP (329 lines)
stream.zig — SSE parser (344 lines)
json.zig — hand-rolled JSON (500 lines)
tools_coding.zig — 7 tools (280 lines)
context.zig — token management (225 lines)

You can read the entire codebase in an hour.

### 6/10 — The Embedded Angle
YoctoClaw has BLE and serial transports built in.

The agent brain runs on hardware:
• $20 smart ring (Colmi R02)
• $3 ESP32-C3
• $6 Raspberry Pi Pico
• nRF5340 dev kit

Your phone bridges to the cloud. The device does the thinking.

### 7/10 — How We Got 180KB
• Zig compiles to native. No runtime.
• Hand-rolled JSON parser — 500 lines vs importing std.json
• Vtable transports — swap HTTP/BLE/serial without code changes
• Fixed arena allocator for embedded (4KB–256KB presets)
• Compile-time feature flags strip unused code paths

Every byte earns its place.

### 8/10 — Why Zig?
We evaluated Go, Rust, C, and Zig.

Go: 8MB binary (YoctoClaw Go exists — 45x larger)
Rust: 3.4MB (ZeroClaw — great, but 19x larger)
C: maximum control, minimum ergonomics
Zig: 180KB + modern tooling + comptime + cross-compilation

Zig hit the sweet spot.

### 9/10 — It's Production Quality
• 39 unit tests across 6 modules
• 9 integration tests
• CI with binary size gate (<300KB)
• Security: no shell injection in search/list, bounded output, RPC escaping
• MIT licensed

This isn't a weekend hack. It's a serious tool.

### 10/10 — Try It
```
git clone github.com/yoctoclaw/TinyDancer
cd TinyDancer
zig build -Doptimize=ReleaseSmall
export ANTHROPIC_API_KEY=...
./zig-out/bin/yoctoclaw "create a REST API with auth"
```

Star it if you think coding agents should be smaller: github.com/yoctoclaw/TinyDancer

Built by @accelerando_ai
