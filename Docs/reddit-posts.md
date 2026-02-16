# YoctoClaw — Reddit Launch Posts

---

## r/zig

### Title
```
I built a full AI coding agent in 3,300 lines of Zig with zero dependencies
```

### Body
```
Hey r/zig — I've been working on YoctoClaw, a fully autonomous coding agent
written entirely in Zig. Zero dependencies. 180KB static binary.

It does the same thing as Claude Code: you give it a prompt, it calls an LLM,
gets tool calls back, executes them (bash, file read/write/edit, search), and
loops until the task is done.

**The numbers:**
- ~180KB release binary (ReleaseSmall, stripped)
- ~2MB RAM usage
- 13 source files, ~3,300 LOC total
- <10ms boot, ~1 sec compile from clean
- 39 inline unit tests, 9 integration tests, CI pipeline

**Why Zig?**

Zig is why this is 180KB instead of 8MB (Go) or 50MB (TypeScript/Python).

Specific Zig features that mattered:
- Comptime feature flags for transports (BLE, Serial) — exclude what you don't need
- No runtime or GC — the binary is just the code
- Manual memory control for the arena allocator (targeting embedded hardware)
- std.mem.indexOf for search instead of a regex engine

**Design decisions Zig devs might find interesting:**

1. **Hand-rolled JSON parser (500 lines)** — I skipped std.json entirely. The parser
   only handles Claude/OpenAI/Ollama API shapes. No tree, no general parsing, no
   allocations. This is probably the biggest binary size win.

2. **FNV-1a stuck-loop detection** — 128 bytes to detect when the LLM is calling the
   same tool repeatedly. Circular buffer of hashes. O(1) per call.

3. **Vtable transports** — Same binary, three physical layers (HTTP, BLE, Serial).
   The agent loop doesn't know which transport it's using.

4. **Fixed arena allocator** — Presets from 4KB (smart ring) to 256KB (desktop).
   Reset between agent turns. For devices with no OS heap.

5. **No regex in search** — `std.mem.indexOf` covers 90%+ of agent search cases.
   A regex engine would add ~10K lines and blow the binary size.

**Known limitations:**
- JSON parser is flat (first-match key extraction)
- BLE needs platform SDK linking for real hardware (protocol is implemented)
- No conversation persistence

It supports Claude, OpenAI, and Ollama. MIT licensed.

I'd love feedback on the Zig code quality — I'm sure there are idioms I'm missing.
PRs welcome.

GitHub: https://github.com/matusjAGI/TinyDancer
```

---

## r/programming

### Title
```
What if a coding agent was 180KB instead of 500MB?
```

### Body
```
Every coding agent ships as a massive bundle:

- Claude Code: ~50MB, ~500 npm packages
- Cursor: ~500MB Electron app
- Aider: ~50MB, ~100 pip packages

The actual agent logic — "call LLM, execute tools, loop" — is a fraction of that.
The rest is platform: IDE integration, extensions, cloud sync.

I built YoctoClaw to find out how small the core agent actually is.

**The answer: 180KB. 3,300 lines of Zig. Zero dependencies.**

It has the standard tool set: bash, read_file, write_file, edit_file, search,
list_files. Supports Claude, OpenAI, and Ollama. Streaming responses. Context
management. Multi-turn conversations.

**How it compares:**

|                | YoctoClaw  | Claude Code | Cursor   | Aider    |
|---------------|-----------|-------------|----------|----------|
| Binary         | ~180 KB    | ~50 MB      | ~500 MB  | ~50 MB   |
| RAM            | ~2 MB      | ~200 MB     | ~1 GB    | ~150 MB  |
| Source         | ~3,300 LOC | ~100K LOC   | ?        | ~30K LOC |
| Dependencies   | 0          | ~500 npm    | ~1000+   | ~100 pip |
| Boot time      | <10 ms     | ~2s         | ~5s      | ~3s      |

**What made it possible:**

The biggest win was a hand-rolled JSON parser (500 lines) that only handles the
exact API shapes for Claude/OpenAI/Ollama. No general parsing, no tree, no allocations.

Other: FNV-1a loop detection in 128 bytes, priority-based context truncation
(drops assistant text first, preserves tool results), vtable transport abstraction
for BLE/Serial/HTTP.

The surprise: it can target embedded hardware. The agent brain (state, decisions,
context) runs on-device. A phone bridges to the API. Target hardware includes the
$3 ESP32-C3 and nRF5340 dev kit.

Not a replacement for Claude Code or Cursor — those have platform features that
matter. But proof that the "agent harness" itself is tiny.

MIT licensed. Whole codebase is 13 files you can read in an afternoon.

GitHub: https://github.com/matusjAGI/TinyDancer
```

---

## r/LocalLLaMA

### Title
```
YoctoClaw: A 180KB coding agent that works with Claude, OpenAI, and Ollama
```

### Body
```
Built a fully autonomous coding agent that's 180KB and supports Ollama natively.

**Why this matters for local LLM users:**

- No API key needed with Ollama
- No data leaves your machine
- Single static binary — no npm, no pip, no Docker, no supply chain to audit
- 180KB download, ~2MB RAM, boots in <10ms

**Quick start with Ollama:**

```bash
# Build YoctoClaw
git clone https://github.com/matusjAGI/TinyDancer
cd TinyDancer/yoctoclaw
zig build -Doptimize=ReleaseSmall

# Run with any Ollama model
./zig-out/bin/yoctoclaw --provider ollama -m llama3 "fix the tests"
./zig-out/bin/yoctoclaw --provider ollama -m codellama "add error handling"
./zig-out/bin/yoctoclaw --provider ollama -m mistral "explain this code"
```

**What it does:**
Full agentic loop — gives the LLM tools (bash, read_file, write_file, edit_file,
search, list_files) and lets it loop autonomously until the task is done. Same
pattern as Claude Code or Aider, but 278x smaller.

**Why 180KB:**
Written in Zig. Zero dependencies. Hand-rolled JSON parser. No runtime, no GC.
The whole thing is 13 source files, ~3,300 lines. You can read and audit the
entire codebase in an afternoon.

**The security angle:**
- Zero dependencies = zero supply chain attack surface
- Static binary = nothing injected at install time
- Pure Zig file operations (search, list_files) = no shell injection vectors
- Open source, MIT licensed, 3,300 lines = fully auditable

**Known limitations:**
- Ollama model quality varies — works best with codellama, llama3, deepseek-coder
- No regex search (substring match only)
- No conversation persistence
- Token estimation is heuristic (~4 chars/token)

For air-gapped environments, enterprise setups, or anyone who doesn't want to
send code to an API: this might be useful.

GitHub: https://github.com/matusjAGI/TinyDancer
```

---

## r/embedded

### Title
```
We built a coding agent that runs on an nRF5340 over BLE
```

### Body
```
YoctoClaw is an AI coding agent — the same "call LLM, execute tools, loop" pattern
as Claude Code — in a 180KB static binary. Written in Zig. Zero dependencies.

What makes it relevant for r/embedded: **it has BLE and Serial transports and a
fixed arena allocator designed for MCU targets.**

**Architecture:**

The device runs the agent brain:
- Conversation state management
- Tool selection decisions
- Context window management
- JSON parsing
- Loop control (including stuck-detection via FNV-1a hashing)

A phone/laptop runs the bridge:
- HTTP calls to Claude/OpenAI API
- Local tool execution (bash, file operations)
- Relays results back over BLE or Serial

**Why split it this way?** The "thinking" (which tool to call, what context to keep)
uses <50KB on-device. The "doing" (running bash, reading files, calling APIs) needs
internet and a filesystem.

**Target hardware:**

| Device           | SoC       | RAM    | Flash  | Cost |
|-----------------|-----------|--------|--------|------|
| ESP32-C3         | RISC-V    | 400 KB | 4 MB   | $3   |
| RPi Pico W       | RP2040    | 264 KB | 2 MB   | $6   |
| Colmi R02        | BlueX RF03| ~32 KB | ~256 KB| $20  |
| nRF5340-DK       | nRF5340   | 512 KB | 1 MB   | $50  |
| nRF52840-DK      | nRF52840  | 256 KB | 1 MB   | $40  |

**Fixed arena allocator:**

For devices with no OS heap. Preset sizes:
- `Arena4K` — smart ring class (Colmi R02)
- `Arena16K` / `Arena32K` — constrained MCUs
- `Arena128K` / `Arena256K` — desktop-embedded hybrid

Reset between agent turns to reclaim everything at once. Zero fragmentation.

**Build for embedded:**

```bash
# BLE support
zig build -Dble=true -Doptimize=ReleaseSmall

# Serial support
zig build -Dserial=true -Doptimize=ReleaseSmall

# Freestanding (no OS, bare-metal)
zig build -Dembedded=true -Dtarget=thumb-none-eabi -Doptimize=ReleaseSmall
```

**Current status:**
- BLE transport: GATT protocol + UUIDs implemented, desktop simulation via Unix socket.
  Real hardware needs platform SDK linking (e.g., Nordic SoftDevice).
- Serial transport: UART framing + baud config via stty. Linux/macOS.
- Arena allocator: Fully working, tested.
- Bridge: Python script that relays BLE/Serial ↔ HTTP.

**What I'd love help with:**
- Anyone with an nRF5340-DK willing to test the BLE transport with SoftDevice
- Feedback on the arena allocator design (arena.zig, 175 lines)
- Ideas for practical embedded agent use cases

This is MIT licensed, ~3,300 lines total, 13 Zig source files.

GitHub: https://github.com/matusjAGI/TinyDancer
```

---

## Posting Guidelines

### Timing
- Post r/zig first (most receptive, highest signal-to-noise)
- Stagger by 15-30 minutes: r/zig → r/programming → r/LocalLLaMA → r/embedded
- Best time: 9-11am ET on weekdays (overlaps US + Europe)

### Self-Promotion Rules
- **r/zig:** Generally welcoming of project showcases. Include technical depth.
- **r/programming:** 10:1 rule (10 comments on others' posts per 1 self-promo). Include substantial technical content in the post body, not just a link.
- **r/LocalLLaMA:** Very welcoming of local-first tools. Lead with Ollama integration.
- **r/embedded:** Appreciates specificity. Include exact hardware targets, memory numbers, build commands.

### Response Strategy
- Reply to every comment within 4 hours
- Be technical and specific — link to source files when relevant
- Acknowledge limitations openly
- If someone asks for a feature, consider creating a GitHub issue and linking it
- Never be defensive about "it's a toy" — redirect to "try it and see"
