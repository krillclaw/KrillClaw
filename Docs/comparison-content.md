# YoctoClaw — Comparison Content

---

## Article 1: YoctoClaw vs Claude Code — Same Job, 278x Smaller

### Subtitle
*The entire coding agent harness fits in 180KB. The other 50MB is platform.*

---

Claude Code is Anthropic's official coding agent. It's excellent — smart, well-integrated, actively developed. It's also ~50MB, pulls ~500 npm packages, uses ~200MB of RAM, and takes ~2 seconds to boot.

YoctoClaw does the same core job in 180KB.

This isn't a critique of Claude Code. It's an observation about what "coding agent" actually means.

### What They Share

Both are fully autonomous coding agents. Both follow the same loop:

1. Send conversation + system prompt to an LLM
2. Parse the response for tool calls
3. Execute the tools
4. Append the results to the conversation
5. Send it back to the LLM
6. Repeat until the LLM says "done"

Both have:
- Bash execution
- File read/write/edit
- Search/find tools
- Streaming responses
- Context window management
- Multi-turn conversations

### What Claude Code Has That YoctoClaw Doesn't

| Feature | Claude Code | YoctoClaw |
|---------|------------|-----------|
| IDE integration (VS Code) | Yes | No |
| Extension/plugin system | Yes | No |
| Cloud sync | Yes | No |
| Team collaboration | Yes | No |
| Conversation persistence | Yes | No |
| Git integration | Extensive | Via bash tool |
| Model Context Protocol (MCP) | Yes | No |
| Telemetry & analytics | Yes | No |
| Auto-update | Yes | No |
| Regex search | Yes | No (substring) |
| Image support | Yes | No |
| Web search | Yes | No |

These are real features that matter. If you need IDE integration or team features, use Claude Code.

### What YoctoClaw Has That Claude Code Doesn't

| Feature | YoctoClaw | Claude Code |
|---------|-----------|------------|
| BLE transport (embedded) | Yes | No |
| Serial transport (UART) | Yes | No |
| Fixed arena allocator | Yes | No |
| Runs on $3 MCU | Yes | No |
| Ollama (local LLM) | Yes | No |
| OpenAI support | Yes | No (Claude only) |
| Zero dependencies | Yes | ~500 npm |
| Static binary | Yes | Requires Node.js |
| <10ms boot | Yes | ~2s |

### The Numbers

| Metric | YoctoClaw | Claude Code | Ratio |
|--------|-----------|-------------|-------|
| **Binary size** | ~180 KB | ~50 MB | **278x** |
| **RAM usage** | ~2 MB | ~200 MB | **100x** |
| **Source code** | ~3,300 LOC | ~100,000 LOC | **30x** |
| **Dependencies** | 0 | ~500 npm packages | **∞** |
| **Boot time** | <10 ms | ~2 seconds | **200x** |
| **Compile time** | ~1 second | N/A (interpreted) | — |
| **Providers** | 3 | 1 | **3x** |

### What This Tells Us

The coding agent harness — the core loop of LLM calls, tool execution, context management — is not where the complexity lives. It's ~3,300 lines. The ~97,000 lines that separate YoctoClaw from Claude Code are platform features: IDE, extensions, cloud, collaboration, telemetry, billing.

This isn't a knock on platform features. They're genuinely valuable. But they're not the agent.

YoctoClaw is what you get when you strip everything that isn't agent. 180KB.

### When to Use Which

**Use Claude Code if you:**
- Work primarily in VS Code or an IDE
- Need team collaboration features
- Want the most capable and polished experience
- Don't care about binary size or dependency count

**Use YoctoClaw if you:**
- Want a minimal, auditable agent you can fully understand
- Need to run on embedded or constrained hardware
- Want multi-provider support (Claude + OpenAI + Ollama)
- Care about zero dependencies and supply chain security
- Want to learn how coding agents actually work (13 files to read)

---

## Article 2: Every Coding Agent Ranked by Binary Size

### Subtitle
*From 180KB to 500MB — the full landscape of AI coding agents.*

---

How big does a coding agent need to be? We benchmarked every significant CLI coding agent by binary size, RAM usage, source code, and dependencies.

### The Ranking

| Rank | Agent | Language | Binary | RAM | Source | Deps | Providers | Embedded |
|------|-------|----------|--------|-----|--------|------|-----------|----------|
| 1 | **YoctoClaw** | Zig | **~180 KB** | ~2 MB | ~3,300 LOC | 0 | 3 | Yes |
| 2 | ZeroClaw | Rust | ~3.4 MB | ~15 MB | ~3,000 LOC | many | ? | No |
| 3 | YoctoClaw Go | Go | ~8 MB | ~10 MB | ~5,000 LOC | ~50 | 7 | No |
| 4 | OpenCode | Go | ~15 MB | ~20 MB | ~10,000 LOC | many | ? | No |
| 5 | Aider | Python | ~50 MB* | ~150 MB | ~30,000 LOC | ~100 | 10+ | No |
| 6 | Claude Code | TypeScript | ~50 MB* | ~200 MB | ~100,000 LOC | ~500 | 1 | No |
| 7 | Cursor | TypeScript | ~500 MB | ~1 GB | ? | ~1,000+ | 2 | No |

*\*Including runtime (Node.js / Python)*

### Visualizing the Gap

```
Binary size (log scale):

YoctoClaw     ██ 180 KB
ZeroClaw      ████████████████████ 3.4 MB
PicoClaw Go   ████████████████████████████████████████████████ 8 MB
OpenCode      ███████████████████████████████████████████████████████████████████████████████████████ 15 MB
Aider         ██████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████ 50 MB
Claude Code   ██████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████ 50 MB
Cursor        ████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████ 500 MB
```

### Tier Analysis

#### Tier 1: Ultra-Minimal (<1 MB)

**YoctoClaw (Zig) — 180 KB**

The smallest by a significant margin. Achieves this through: Zig's zero-runtime compilation, hand-rolled JSON parser (no std.json), no regex engine, comptime feature flags. Zero dependencies. Unique in supporting BLE and Serial transports for embedded hardware.

*Tradeoff:* Fewer tools (6 vs 10+), no IDE integration, no conversation persistence, substring search only.

#### Tier 2: Small Compiled (~3–15 MB)

**ZeroClaw (Rust) — 3.4 MB**

Rust's zero-cost abstractions get close to Zig but can't match the extreme minimalism. Cargo dependencies add binary weight. No embedded target.

**YoctoClaw Go — 8 MB**

Go's garbage collector and runtime add ~5MB baseline. Static binary, fast compile. 7 providers but no streaming or edit tool.

**OpenCode (Go) — 15 MB**

More features than YoctoClaw Go (TUI, multiple providers) at the cost of larger binary. Many Go module dependencies.

#### Tier 3: Runtime-Dependent (~50 MB)

**Aider (Python) — 50 MB\***

The most provider-flexible agent (10+ providers). 30K LOC of Python. Requires Python runtime + 100 pip packages. Excellent git integration and chat modes.

**Claude Code (TypeScript) — 50 MB\***

The most full-featured agent. IDE integration, MCP, extensions, team features. Requires Node.js runtime + 500 npm packages. Single-provider (Claude only).

#### Tier 4: Full IDE (>100 MB)

**Cursor (TypeScript) — 500 MB**

Not really a "CLI agent" — it's a full IDE (Electron fork of VS Code). Includes editor, extension system, cloud features. The agent is a small part of the total.

### The White Spaces

| Language | Existing Agents | Opportunity |
|----------|----------------|-------------|
| **C++** | llama-agent (~150 stars, local-only) | Desktop + local llama.cpp integration |
| **C#** | None | First CLI coding agent for .NET ecosystem |
| **C** | MimiClaw (ESP32-S3 only) | True bare-metal agent, smallest possible binary |
| **Swift** | None | macOS-native agent |
| **Java/Kotlin** | None | Enterprise/Android ecosystem |

### What Binary Size Tells Us

Binary size correlates loosely with:
- **Startup time** — smaller binaries boot faster (YoctoClaw: <10ms, Cursor: ~5s)
- **Attack surface** — fewer dependencies = fewer CVEs to track
- **Portability** — static binaries work everywhere, no runtime install
- **Embedded potential** — <1MB is MCU territory

It does NOT correlate with:
- **Agent quality** — Claude Code is the most capable despite being 278x larger
- **Model output** — the same LLM produces the same quality regardless of harness size
- **Feature richness** — platform features legitimately require more code

### The Takeaway

The core agent harness is a solved problem. YoctoClaw proves it fits in 180KB and 3,300 lines. Everything above that — from ZeroClaw's 3.4MB to Cursor's 500MB — is a combination of language runtime overhead, dependency weight, and platform features.

The question isn't "how small can an agent be?" (Answer: 180KB.) The question is: "what platform features are worth the additional 99.96% of binary size?"

For most developers, the answer is "a lot of them." But it's worth knowing what you're paying for.

---

## Bonus: Quick Comparison Cards (for social media)

### Card 1: Size
```
YoctoClaw: 180 KB
Claude Code: 50,000 KB

Same core loop. 278x difference.
```

### Card 2: Dependencies
```
YoctoClaw dependencies:
(this space intentionally left blank)

Claude Code dependencies:
500 npm packages
```

### Card 3: Source
```
YoctoClaw: 13 files. Read them all in an hour.
Claude Code: ~100,000 lines. Good luck.
```

### Card 4: Boot
```
YoctoClaw boots in 10 milliseconds.
In that time, Claude Code is still loading npm.
```

### Card 5: Hardware
```
YoctoClaw runs on:
✓ MacBook Pro
✓ Linux server
✓ $3 ESP32
✓ Smart ring

Claude Code runs on:
✓ MacBook Pro
✓ Linux server
```
