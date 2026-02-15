# YoctoClaw

**The world's smallest coding agent.**

YoctoClaw is a fully autonomous AI coding agent written in Zig. Zero dependencies. One binary. Connects to Claude, OpenAI, or Ollama. Executes tools. Loops until done. Ships under 200KB.

```
 __   __        _         ___  _
 \ \ / /___  __| |_ ___  / __|| | __ ___ __ __
  \ V // _ \/ _|  _/ _ \| (__ | |/ _` \ V  V /
   |_| \___/\__|\__\___/ \___||_|\__,_|\_/\_/
```

## Why?

Every coding agent is a 500MB Electron app or a 50MB Node.js bundle. The actual logic — "call LLM, execute tools, loop" — is ~3,500 LOC (including tests) of Zig and a 180KB binary. YoctoClaw proves it.

## Size

| | YoctoClaw | Claude Code | Cursor | Aider | YoctoClaw Go |
|---|---------|-------------|--------|-------|------------|
| **Binary** | **~150-180 KB** | ~50 MB | ~500 MB | ~50 MB | ~8 MB |
| **RAM** | **~2 MB** | ~200 MB | ~1 GB | ~150 MB | ~10 MB |
| **Source** | **~3,500 LOC (including tests)** | ~100K LOC | ? | ~30K LOC | ~5K LOC |
| **Deps** | **0** | ~500 npm | ~1000+ | ~100 pip | ~50 Go |
| **Boot** | **<10 ms** | ~2s | ~5s | ~3s | <1s |
| **Languages** | **Zig** | TypeScript | TypeScript | Python | Go |
| **Providers** | **3** | 1 | 2 | 10+ | 1 |
| **BLE/Embedded** | **Yes** | No | No | No | No |

> Source count: ~2,800 lines of core logic + ~500 lines of inline tests. The entire project — including build system, bridge, and integration tests — is under 4,000 lines.

## Quick Start

```bash
# Install Zig 0.13+ from https://ziglang.org/download/

# Build (release binary, stripped)
cd yoctoclaw
zig build -Doptimize=ReleaseSmall

# Set API key
export ANTHROPIC_API_KEY=sk-ant-...

# Run interactively
./zig-out/bin/yoctoclaw

# One-shot
./zig-out/bin/yoctoclaw "create a REST API in Go with user auth"

# Use OpenAI
export OPENAI_API_KEY=sk-...
./zig-out/bin/yoctoclaw --provider openai -m gpt-4o "fix the tests"

# Use local Ollama
./zig-out/bin/yoctoclaw --provider ollama -m llama3 "explain this code"
```


## Profiles

YoctoClaw supports compile-time profiles that select different tool sets for different use cases. Only the selected profile's code is compiled into the binary — zero runtime overhead.

```bash
# Coding agent (default) — bash, read/write/edit files, search, apply_patch
zig build -Dprofile=coding -Doptimize=ReleaseSmall

# IoT agent — MQTT pub/sub, HTTP requests, key-value store, device info
zig build -Dprofile=iot -Doptimize=ReleaseSmall

# Robotics agent — robot commands with bounds checking, e-stop, telemetry
zig build -Dprofile=robotics -Doptimize=ReleaseSmall

# Any profile with sandbox restrictions (no network, restricted fs, simulated backends)
zig build -Dsandbox=true -Doptimize=ReleaseSmall
zig build -Dprofile=iot -Dsandbox=true -Doptimize=ReleaseSmall
```

| Profile | Tools | Binary Size | Policy |
|---------|-------|-------------|--------|
| **coding** | bash, read/write/edit_file, search, list_files, apply_patch | ~180 KB | bash behind approval gate, writes restricted to cwd |
| **iot** | publish_mqtt, subscribe_mqtt, http_request, kv_get/set, device_info | ~150 KB | no bash, no file writes, 30 req/min rate limit |
| **robotics** | robot_cmd (pose/velocity/gripper), estop, telemetry_snapshot | ~160 KB | no bash, no file writes, bounds checking, 10 cmd/s rate limit, e-stop |

## Features

### Core Agent
- Full agentic loop: prompt → LLM → tools → repeat
- Streaming responses (SSE) with real-time output
- Context window management with priority-based truncation
- Multi-turn conversations in REPL mode
- Token tracking and usage reporting
- Stuck-loop detection (FNV-1a hash of recent tool calls)

### Tools (6)
| Tool | Description |
|------|-------------|
| `bash` | Execute any shell command |
| `read_file` | Read file contents |
| `write_file` | Create or overwrite files |
| `edit_file` | Find-and-replace in files (exact match, must be unique) |
| `search` | Search for text patterns across files (pure Zig, no shell) |
| `list_files` | List files with optional glob filter (pure Zig, no shell) |

### Providers (3)
| Provider | Models | Auth |
|----------|--------|------|
| **Claude** | claude-sonnet-4-5, claude-opus-4, etc. | `ANTHROPIC_API_KEY` |
| **OpenAI** | gpt-4o, gpt-4-turbo, etc. | `OPENAI_API_KEY` |
| **Ollama** | llama3, codellama, mistral, etc. | None (local) |

### Transport Layers
| Transport | Use Case | Status |
|-----------|----------|--------|
| **HTTP** | Desktop — direct HTTPS to API | Stable |
| **BLE** | Embedded — GATT protocol + desktop simulation via Unix socket | Experimental |
| **Serial** | Dev boards — UART to host machine (Linux/macOS) | Experimental |

> **Note on BLE/embedded:** The BLE transport implements the framing protocol and GATT service UUIDs, with desktop simulation via Unix sockets. Real hardware integration (nRF5340, nRF52840) requires linking against the platform's BLE SDK (e.g., Nordic SoftDevice). The transport abstraction is designed for this — see `ble.zig` for the integration points.

### Config
```bash
# Environment variables
export YOCTOCLAW_MODEL=claude-opus-4-6
export YOCTOCLAW_PROVIDER=claude
export YOCTOCLAW_BASE_URL=https://my-proxy.com
export YOCTOCLAW_SYSTEM_PROMPT="You are a Go expert..."

# Or use a config file: .yoctoclaw.json
{
  "model": "claude-sonnet-4-5-20250929",
  "provider": "claude",
  "max_tokens": 8192,
  "streaming": true
}
```

## Core vs Add-on Components

| Component | What's Included | Source | Est. Binary Delta | Compile Flag |
|-----------|----------------|--------|-------------------|--------------|
| **Core** | Agent loop, API client, SSE streaming, JSON parser, 6 tools, context mgmt, config, transport abstraction | 2,825 lines (10 files) | ~180 KB | *(default)* |
| **BLE Transport** | GATT protocol, Unix socket simulation, chunk framing | 159 lines | ~+5 KB | `-Dble=true` |
| **Serial Transport** | UART framing, baud config, length-prefixed protocol | 142 lines | ~+3 KB | `-Dserial=true` |
| **Arena Allocator** | Fixed-size memory for embedded, preset sizes (4K–256K), peak tracking | 175 lines | ~+2 KB | `-Dembedded=true` |
| **Bridge (Python)** | BLE/Serial ↔ HTTP relay, local tool execution | 301 lines | 15 KB download | N/A (separate) |

### vs YoctoClaw Go

| Metric | YoctoClaw Zig | YoctoClaw Go | Ratio |
|--------|:---:|:---:|:---:|
| **Binary** | ~180 KB | ~8 MB | **45x smaller** |
| **RAM** | ~2 MB | ~10 MB | **5x less** |
| **Source (core)** | ~2,800 LOC | ~4,000 LOC | 1.4x less |
| **Dependencies** | 0 | ~50 Go mods | -- |
| **Compile time** | ~1 sec | ~5 sec | 5x faster |
| **Boot time** | <10 ms | <1 sec | ~100x faster |
| **Providers** | 3 (Claude, OpenAI, Ollama) | 1 (Claude) | 3x |
| **Streaming** | Yes (SSE) | No | -- |
| **BLE/Embedded** | Yes | No | -- |
| **Garbage collector** | None | Go GC | -- |

## Architecture

```
src/
├── main.zig        # CLI, REPL, entry point                           (152 lines)
├── agent.zig       # Agent loop + FNV-1a stuck-loop detection         (250 lines)
├── api.zig         # Multi-provider HTTP client (Claude/OpenAI/Ollama)(329 lines)
├── stream.zig      # SSE streaming parser with safe string ownership  (344 lines)
├── json.zig        # JSON build + extract — zero deps, hand-rolled    (500 lines)
├── tools.zig       # Tool dispatcher — comptime profile selection         (140 lines)
├── tools_coding.zig # Coding profile: 7 tools + path allowlist            (280 lines)
├── tools_iot.zig    # IoT profile: 6 bridge tools + rate limiting         (95 lines)
├── tools_robotics.zig # Robotics profile: 3 tools + bounds/e-stop         (155 lines)
├── context.zig     # Token estimation + priority-based truncation     (225 lines)
├── config.zig      # Config: file → env → CLI, with precedence       (184 lines)
├── transport.zig   # Abstract vtable transport + RPC protocol         (129 lines)
├── types.zig       # Core types: Provider, Message, Config, ToolDef   (194 lines)
├── ble.zig         # BLE GATT transport (protocol + simulation)       (159 lines)
├── serial.zig      # UART/serial transport (Linux/macOS)              (142 lines)
└── arena.zig       # Fixed arena allocator for embedded targets       (175 lines)

bridge/
├── bridge.py       # BLE/Serial ↔ HTTP bridge + tool executor         (301 lines)
└── requirements.txt

test/
└── integration.sh  # CLI smoke + integration tests                    (92 lines)
```

16 Zig files. ~3,500 LOC (including tests). 1 Python bridge. Zero Zig dependencies.

## Architecture Decisions

**Why hand-rolled JSON?** — A full JSON parser (even Zig's `std.json`) adds unnecessary code and allocations. YoctoClaw only needs to extract specific keys from API responses and build request bodies. The custom 500-line parser/builder handles both with zero dependencies.

**Why vtable transports?** — The same agent binary should work over HTTP (desktop), BLE (smart ring), or Serial (dev board). The vtable pattern lets us swap the physical layer without changing the agent loop, and feature flags keep the binary small when a transport isn't needed.

**Why FNV-1a loop detection?** — If the LLM calls the same tool with the same input 3+ times, it's stuck. Tracking the last 8 tool calls via FNV-1a hashes uses constant memory (128 bytes) and O(1) per call — critical for embedded targets.

**Why priority-based truncation?** — When the context window fills up, not all messages are equally valuable. Tool results (small, high-information) are preserved longest. Assistant text (large, redundant) is dropped first. This keeps the agent's working memory functional under pressure.

**Why no regex in `search`?** — The search tool uses `std.mem.indexOf` (substring match), not regex. This is intentional: regex engines are large (~10K+ lines), and substring match covers 90%+ of agent search use cases. The tool schema clearly documents "substring match".

## Embedded / Smart Ring Mode

YoctoClaw can target microcontrollers with BLE. The device runs the agent brain (loop, decisions, state). A phone/laptop bridges to the internet and executes tools.

```
┌─────────────┐       BLE/UART       ┌──────────────┐      HTTPS      ┌─────────┐
│  YoctoClaw   │ ◄───────────────────► │   Bridge     │ ◄─────────────► │ Claude  │
│  (device)   │                       │ (phone/PC)   │                 │ API     │
│             │                       │              │                 └─────────┘
│ Agent loop  │  "call bash ls"       │ Executes     │
│ JSON parse  │ ──────────────►       │ tools locally│
│ State mgmt  │                       │ Returns      │
│             │  ◄──────────────      │ results      │
│             │  "file1 file2..."     │              │
└─────────────┘                       └──────────────┘
    ~50 KB                              bridge.py
```

### Build for embedded

```bash
# With BLE support
zig build -Dble=true -Doptimize=ReleaseSmall

# With serial support
zig build -Dserial=true -Doptimize=ReleaseSmall

# Freestanding (no OS, for bare-metal MCUs)
zig build -Dembedded=true -Dtarget=thumb-none-eabi -Doptimize=ReleaseSmall
```

### Run the bridge

```bash
cd bridge
pip install -r requirements.txt

# BLE mode (scans for YoctoClaw device)
python bridge.py --ble

# Serial mode
python bridge.py --serial /dev/ttyUSB0

# Desktop simulation (Unix socket)
python bridge.py --socket /tmp/yoctoclaw.sock
```

### Target Hardware

| Device | SoC | RAM | Flash | Cost | Notes |
|--------|-----|-----|-------|------|-------|
| **Colmi R02** | BlueX RF03 | ~32 KB | ~256 KB | $20 | Hackable smart ring |
| **nRF5340-DK** | nRF5340 | 512 KB | 1 MB | $50 | Dev kit |
| **nRF52840-DK** | nRF52840 | 256 KB | 1 MB | $40 | Dev kit |
| **ESP32-C3** | RISC-V | 400 KB | 4 MB | $3 | WiFi + BLE |
| **Raspberry Pi Pico W** | RP2040 | 264 KB | 2 MB | $6 | WiFi + BLE |

### Fixed Arena Allocator

For devices with no OS heap:

```zig
const arena = @import("arena.zig");

// 32KB arena — fits on nRF5340
var mem = arena.Arena32K.init();
const alloc = mem.allocator();

// Use alloc for everything...

// Reset between agent turns (frees everything at once)
mem.reset();
```

Pre-defined sizes: `Arena4K`, `Arena16K`, `Arena32K`, `Arena128K`, `Arena256K`.

## Sandbox Mode

Use `-Dsandbox=true` for restricted execution. This prevents network access, limits file operations to the working directory, and runs bash commands in an isolated environment.

```bash
# Coding profile: bash runs in /tmp/yoctoclaw-sandbox with empty PATH, file ops restricted to cwd
zig build -Dsandbox=true -Doptimize=ReleaseSmall

# IoT/Robotics profiles: bridge calls return simulated data (no real MQTT/HTTP/robot commands)
zig build -Dprofile=iot -Dsandbox=true -Doptimize=ReleaseSmall
```

## Security

YoctoClaw executes tools on the host system with the permissions of the running user. Like all coding agents (Claude Code, Aider, Cursor), it can execute arbitrary commands when instructed by the LLM. **Do not run YoctoClaw with elevated privileges.** Use the policy system to restrict tool access.

BLE and Serial transports do not currently include encryption or authentication. Use only on trusted networks.

To report security issues, email [security contact].

## Build

```bash
# Debug (good errors, larger binary)
zig build

# Release (smallest binary)
zig build -Doptimize=ReleaseSmall

# Check binary size
ls -la zig-out/bin/yoctoclaw

# Run tests (39 unit tests across 6 modules)
zig build test

# Report size
zig build size
```

## Testing

- **39 inline unit tests** covering JSON parsing, SSE streaming, arena allocation, context truncation, tool execution, and glob matching
- **9 integration tests** in `test/integration.sh` (CLI flags, error handling, binary size gate)
- **CI pipeline** in `.github/workflows/test.yml` with binary size gate (<300KB)
- **Security tests** for injection attempts in search, list_files, and edit_file

## REPL Commands

| Command | Description |
|---------|-------------|
| `/help` | Show help |
| `/quit` `/exit` `/q` | Exit |
| `/model <name>` | Switch model |
| `/model` | Show current model |
| `/provider <name>` | Switch provider (claude/openai/ollama) |

## Known Limitations

- **JSON parser is flat:** `extractString` finds the first matching key at any nesting depth, not necessarily the top-level key. Works correctly for Claude/OpenAI API responses where key names are unambiguous.
- **Token estimation is heuristic:** Uses ~4 chars/token approximation. Accurate enough for context management, not for billing.
- **Search is substring, not regex:** The `search` tool uses `std.mem.indexOf` (substring match). This is intentional — a regex engine would add ~10K+ lines. Covers 90%+ of agent search needs.
- **BLE transport is protocol-only:** GATT framing and UUIDs are implemented. Desktop simulation works via Unix socket. Real hardware requires linking against the platform BLE SDK (e.g., Nordic SoftDevice).
- **Serial baud config uses `stty`:** Linux/macOS only. Errors are non-fatal. A future version could use termios ioctl for portability.
- **No conversation persistence:** Sessions start fresh. Context is managed in-memory only.
- **Requires Zig 0.13+:** Built against the Zig 0.13 standard library API.

## License

MIT
