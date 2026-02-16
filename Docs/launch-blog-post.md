# Why We Built a Coding Agent in 3,300 Lines of Zig

*By Accelerando AI*

---

Every coding agent you can download today is enormous.

Claude Code: ~50MB, ~500 npm packages, ~100,000 lines of TypeScript. Cursor: ~500MB. Aider: ~50MB of Python. Even the lean ones — OpenCode, Continue — pull in tens of megabytes of runtime and hundreds of dependencies.

We kept asking: how much of that is the agent?

Not the IDE integration. Not the extension marketplace. Not the cloud sync, the telemetry, the A/B testing, the billing system. Just the agent — the loop that calls an LLM, executes tools, and repeats.

We built YoctoClaw to find out.

---

## The Experiment

The rules were simple:

1. Build a fully autonomous coding agent — prompt, LLM, tools, loop until done.
2. Support multiple providers — Claude, OpenAI, Ollama.
3. Include the standard tool set — bash, read_file, write_file, edit_file, search, list_files.
4. Streaming responses, context management, multi-turn conversations.
5. No dependencies. Not one. Everything from scratch in Zig.
6. Target the smallest possible binary.

The result: **180KB**. A binary smaller than most JPEG photos.

---

## What's in 3,300 Lines

Thirteen source files. Here's every one of them:

| File | Lines | What It Does |
|------|-------|-------------|
| `main.zig` | 152 | CLI parsing, REPL, entry point |
| `agent.zig` | 250 | The agentic loop + stuck-detection |
| `api.zig` | 329 | Multi-provider HTTP client (Claude/OpenAI/Ollama) |
| `stream.zig` | 344 | SSE streaming parser |
| `json.zig` | 500 | Hand-rolled JSON builder + extractor |
| `tools.zig` | 534 | All 6 tools — injection-safe, pure-Zig file ops |
| `context.zig` | 225 | Token estimation + priority-based truncation |
| `config.zig` | 184 | Config: file → env → CLI precedence |
| `transport.zig` | 129 | Abstract vtable transport + RPC |
| `types.zig` | 194 | Core types: Provider, Message, Config, ToolDef |
| `ble.zig` | 159 | BLE GATT transport |
| `serial.zig` | 142 | UART/serial transport |
| `arena.zig` | 175 | Fixed arena allocator for embedded |

That's ~2,800 lines of core logic and ~500 lines of inline tests. You can read the entire thing in an afternoon.

---

## How It Compares

| | YoctoClaw | Claude Code | Cursor | Aider |
|---|---------|-------------|--------|-------|
| **Binary** | **~180 KB** | ~50 MB | ~500 MB | ~50 MB |
| **RAM** | **~2 MB** | ~200 MB | ~1 GB | ~150 MB |
| **Source** | **~3,300 LOC** | ~100K LOC | ? | ~30K LOC |
| **Dependencies** | **0** | ~500 npm | ~1000+ | ~100 pip |
| **Boot time** | **<10 ms** | ~2s | ~5s | ~3s |
| **Providers** | **3** | 1 | 2 | 10+ |

Same job. The binary is 278x smaller than Claude Code. 2,778x smaller than Cursor.

---

## Five Engineering Decisions That Made It Possible

### 1. Hand-Rolled JSON (500 lines)

The biggest decision. Zig's `std.json` is a general-purpose parser — it handles any valid JSON, allocates dynamically, and produces a tree you can walk. We don't need any of that.

YoctoClaw talks to exactly three API formats: Claude, OpenAI, and Ollama. We know the exact shape of every request and response. So we wrote a JSON builder that constructs API requests field-by-field, and an extractor that pulls specific keys from response bodies using direct string scanning.

No allocations. No tree. No generality. 500 lines that handle exactly what we need and nothing more.

### 2. FNV-1a Loop Detection (128 bytes)

If an LLM calls `bash("ls")` three times in a row with the same input, it's stuck. On a desktop, a stuck loop wastes API credits. On an embedded device with a metered BLE connection, it's a disaster.

YoctoClaw tracks the last 8 tool calls using FNV-1a hashes. Each tool invocation is hashed (tool name + arguments) and stored in a circular buffer. If the same hash appears 3+ times in the buffer, the agent injects a "you appear to be stuck" message.

Total memory: 128 bytes. Cost per tool call: O(1). No heap allocation.

### 3. Vtable Transport Abstraction

The same YoctoClaw binary should work over:
- **HTTP** — direct HTTPS to Claude/OpenAI/Ollama (desktop)
- **BLE** — GATT protocol to a phone bridge (smart ring, wearable)
- **Serial** — UART to a host machine (dev board)

This is a classic vtable pattern. The agent loop calls `transport.send()` and `transport.recv()`. At compile time, feature flags determine which transports are included. If you build with `-Dble=true`, BLE is linked in (~5KB). If not, it's excluded completely.

### 4. Priority-Based Context Truncation

Every coding agent hits the context window eventually. The question is: what do you drop?

Most agents truncate from the beginning — first in, first out. YoctoClaw assigns priorities:
- **Assistant text** (lowest priority) — large, often redundant. Dropped first.
- **User messages** (medium) — important but often restated. Dropped second.
- **Tool results** (highest priority) — small, high-information. Preserved longest.

The first user message and last 4 messages are always preserved. This keeps the agent functional even when context is severely constrained — exactly what you need on embedded hardware.

### 5. No Regex

The `search` tool uses `std.mem.indexOf` — substring match, not regex. A proper regex engine is 10,000+ lines. Substring match covers 90%+ of agent search use cases ("find the function called foo", "where is the error message").

The tool schema explicitly says "substring match" so the LLM knows what it's working with. No pretense. No half-implemented regex that breaks on edge cases.

---

## The Surprising Part: It Runs on Embedded Hardware

When we started, embedded was a stretch goal. But the discipline of writing small, allocation-aware code unlocked something unexpected: YoctoClaw can genuinely target microcontrollers.

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
```

The device runs the agent brain: conversation state, tool selection, context management. A phone or laptop bridges it to the internet and executes tools.

Target hardware:

| Device | Cost | Flash | Notes |
|--------|------|-------|-------|
| ESP32-C3 | $3 | 4 MB | WiFi + BLE, RISC-V |
| Raspberry Pi Pico W | $6 | 2 MB | WiFi + BLE |
| Colmi R02 | $20 | ~256 KB | Smart ring |
| nRF5340-DK | $50 | 1 MB | Nordic dev kit |

The fixed arena allocator handles memory for devices with no OS heap. Preset sizes from 4KB (smart ring class) to 256KB (desktop-embedded hybrid). Reset between agent turns to reclaim everything at once. Zero fragmentation.

---

## What We Learned

**The agent harness is a solved problem.** The core loop — call LLM, parse response, execute tools, manage context, repeat — fits in 3,300 lines. The 97,000 lines that separate YoctoClaw from Claude Code aren't agent logic. They're platform: IDE integration, extensions, cloud sync, collaboration, telemetry.

This doesn't make Claude Code bad — those platform features are genuinely valuable. But it does mean the "agent harness" isn't where the complexity lives. The harness is simple. The platform is hard.

**Constraints breed quality.** Targeting embedded hardware forced every allocation to be intentional, every dependency to be justified, every line to earn its place. The desktop binary is better because we designed for the smart ring.

**Zero dependencies is underrated.** No supply chain risk. No version conflicts. No transitive dependency surprises. `zig build` takes one second and produces a static binary that works everywhere. That's it.

---

## Try It

```bash
# Install Zig 0.13+ from ziglang.org/download
git clone https://github.com/matusjAGI/TinyDancer
cd TinyDancer/yoctoclaw
zig build -Doptimize=ReleaseSmall

export ANTHROPIC_API_KEY=sk-ant-...
./zig-out/bin/yoctoclaw "create a REST API in Go with user auth"
```

Three providers. Six tools. One binary. 180KB.

Works with Claude, OpenAI, and Ollama (fully local, no API key needed).

MIT licensed. Star it on [GitHub](https://github.com/matusjAGI/TinyDancer).

---

*Built by [Accelerando AI](https://accelerando.ai). Follow us on [Twitter/X](https://twitter.com/AccelerandoAI) for technical deep-dives on the architecture.*
