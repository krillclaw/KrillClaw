# YoctoClaw — Twitter/X Launch Threads

## Thread 1: Launch Day (The Main Thread)

### Tweet 1/5 — The Hook
```
We built a full coding agent in 3,300 lines of Zig.

The binary is 180KB. Smaller than a JPEG.

It has the same tools as Claude Code:
→ bash
→ read_file
→ write_file
→ edit_file
→ search
→ list_files

Three providers. Zero dependencies. One binary.

🧵👇
```

### Tweet 2/5 — The Comparison
```
How it compares:

              Binary    RAM      Deps
YoctoClaw     180 KB    2 MB     0
Claude Code   50 MB     200 MB   500
Cursor        500 MB    1 GB     1000+
Aider         50 MB     150 MB   100

Same job. 278x smaller than Claude Code.

Boots in <10ms. Compiles in ~1 second.
```

### Tweet 3/5 — The Embedded Angle
```
It also has BLE and serial transports.

The agent brain can run on:
• A $3 ESP32-C3
• A $6 Raspberry Pi Pico
• A $20 smart ring (Colmi R02)
• An nRF5340 dev kit

Your phone bridges it to Claude. The device does the thinking.

180KB fits in flash with room to spare.
```

### Tweet 4/5 — The Technical Flex
```
How we got to 180KB:

• Zig compiles to native. No runtime. No GC.
• Hand-rolled JSON parser — 500 lines, exact shapes only.
• FNV-1a stuck-loop detection — 128 bytes of memory.
• Priority-based context truncation — keeps tools, drops fluff.
• No regex engine (~10K lines). Substring search covers 90%.

13 files. Read them all in an hour.
```

### Tweet 5/5 — The CTA
```
YoctoClaw is MIT licensed.

zig build -Doptimize=ReleaseSmall
export ANTHROPIC_API_KEY=...
./yoctoclaw "create a REST API with auth"

Works with Claude, OpenAI, and Ollama (fully local).

No npm. No pip. No Docker. One static binary.

⭐ github.com/matusjAGI/TinyDancer

Built by @AccelerandoAI
```

---

## Thread 2: Day 2 — "Hand-Rolled JSON in 500 Lines"

### Tweet 1/4
```
The biggest reason YoctoClaw is 180KB: we skipped std.json.

Instead we wrote a 500-line JSON parser that handles exactly what we need — Claude, OpenAI, and Ollama API shapes — and nothing else.

Here's what that looks like 🧵
```

### Tweet 2/4
```
Most JSON parsers:
1. Tokenize the entire input
2. Build a tree (object, array, string nodes)
3. Let you walk/query the tree

That's general-purpose. Handles any JSON. Allocates memory for the full structure.

We don't need any of that.
```

### Tweet 3/4
```
YoctoClaw's JSON:

Builder: constructs API request bodies field-by-field. No intermediate tree. Direct string assembly.

Extractor: scans response bodies for specific keys. Finds "content", "tool_use", "stop_reason" by direct string search.

No allocations. No tree. No generality.
```

### Tweet 4/4
```
The tradeoff is real: our parser can't handle arbitrary JSON. It's "flat" — extractString finds the first matching key at any depth.

But for Claude/OpenAI/Ollama responses, where key names are unambiguous? It works perfectly.

500 lines instead of 5,000. That's ~60KB of binary saved.

Source: github.com/matusjAGI/TinyDancer
```

---

## Thread 3: Day 4 — "The Embedded Architecture"

### Tweet 1/4
```
What does it mean for a coding agent to "run on a smart ring"?

It doesn't mean the ring executes bash commands. Here's how the architecture actually works 🧵
```

### Tweet 2/4
```
The device (ring/MCU) runs the agent BRAIN:
→ Conversation state
→ Context window management
→ Tool selection decisions
→ JSON parsing
→ Loop control

A phone or laptop runs the BRIDGE:
→ HTTP calls to Claude/OpenAI
→ Local tool execution (bash, file ops)
→ Relay results back over BLE/Serial
```

### Tweet 3/4
```
Why split it this way?

The "thinking" (which tool to call, when to stop, what context to keep) uses <50KB on-device.

The "doing" (running bash, reading files, calling APIs) requires internet and a filesystem.

The ring thinks. The phone acts.
```

### Tweet 4/4
```
The transport layer is a vtable — the agent loop calls send() and recv() without knowing if it's HTTP, BLE, or Serial.

Compile flags control which transports are included:
zig build -Dble=true    → +5KB
zig build -Dserial=true → +3KB

Fixed arena allocator: 4KB to 256KB presets. Reset between turns. Zero fragmentation.

Source: github.com/matusjAGI/TinyDancer
```

---

## Thread 4: Day 7 — "The Agent Harness Thesis"

### Tweet 1/4
```
"The moat is your agent harness, not your model."
— @aakashg0

I agree. But I think the harness is much simpler than people assume.

YoctoClaw is a full coding agent in 180KB and 3,300 lines of Zig. Here's what that means for the "moat" thesis 🧵
```

### Tweet 2/4
```
Claude Code: ~100,000 lines of TypeScript
YoctoClaw:   ~3,300 lines of Zig

Same core loop:
1. Send conversation to LLM
2. Parse response for tool calls
3. Execute tools
4. Append results
5. Repeat until done

The ~97,000 line difference isn't agent logic.
It's platform: IDE, extensions, cloud, telemetry.
```

### Tweet 3/4
```
The agent harness — the actual loop that makes a coding agent autonomous — is a solved problem.

Context management: ~225 lines
Tool execution: ~534 lines
API client: ~329 lines
Streaming parser: ~344 lines
Agent loop: ~250 lines

Total: ~1,700 lines for the core.
The rest is JSON parsing, config, and transports.
```

### Tweet 4/4
```
The real moat isn't harness SIZE. It's harness DENSITY.

More capability per byte. More agent per kilobyte.

Claude Code invests in platform (IDE, cloud, team). That's genuinely valuable.

YoctoClaw invests in density. 180KB. Every line earns its place.

Different bets. Both valid.

⭐ github.com/matusjAGI/TinyDancer
```

---

## Thread 5: Day 10 — "Ollama + YoctoClaw = Fully Local AI Coding"

### Tweet 1/3
```
You can run a fully autonomous coding agent without any API key.

YoctoClaw + Ollama = local AI coding on your machine.

No data leaves your network. No API costs. No telemetry.

Here's the setup (30 seconds) 🧵
```

### Tweet 2/3
```
1. Install Ollama: ollama.com
2. Pull a model: ollama pull llama3
3. Build YoctoClaw: zig build -Doptimize=ReleaseSmall
4. Run:

./yoctoclaw --provider ollama -m llama3 "fix the tests"

That's it. No API key. No account. No internet needed after model download.

One 180KB binary. One local model. Full autonomy.
```

### Tweet 3/3
```
Why this matters:

• Air-gapped environments (govt, defense, finance)
• No API cost for experimentation
• Zero data exfiltration risk
• No vendor lock-in
• Works offline after setup

YoctoClaw is a single static binary. No npm supply chain. No pip packages. Nothing to audit except 3,300 lines of Zig.

⭐ github.com/matusjAGI/TinyDancer
```

---

## Engagement Playbook

### Day-of rules:
- Reply to every comment in the first 6 hours
- Quote-retweet anyone who shares the thread with a "thanks" + additional fact
- If someone asks "but can it do X?" — answer honestly. "Not yet" is fine. "That's a great first PR" is better.

### Amplification targets (@ on launch day):
- @mitchellh (Zig + Ghostty)
- @ThePrimeagen (anti-Electron, systems languages)
- @simonw (AI tools coverage)
- @andrewkelley (Zig creator)
- @aakashg0 (agent harness thesis — quote-tweet on day 7)

### Hashtags (use sparingly, 1-2 per thread):
`#zig` `#ziglang` `#ai` `#coding` `#opensource` `#embedded`
