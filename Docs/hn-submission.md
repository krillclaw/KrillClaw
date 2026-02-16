# YoctoClaw — Hacker News Submission Plan

## Submission Details

### Title (primary)
```
Show HN: YoctoClaw – A full coding agent in 3,300 lines of Zig (180KB binary)
```

### Title (alternatives — use if primary feels too long)
```
Show HN: YoctoClaw – The world's smallest coding agent, written in Zig
```
```
Show HN: A coding agent small enough to run on a smart ring (180KB, Zig)
```

### URL
```
https://github.com/matusjAGI/TinyDancer
```

---

## Submission Timing

**Best window:** Tuesday or Wednesday, 9:00–10:00 AM ET

**Why:**
- HN traffic peaks US business hours, especially mornings
- Tuesday/Wednesday have highest front-page retention
- Monday: people catching up on weekend threads
- Thursday: front page gets crowded by end-of-week posts
- Friday: posts die over the weekend

**Avoid:** Fridays, weekends, holidays, major Apple/Google/AI announcement days.

**Backup timing:** If the first submission doesn't gain traction in 2 hours (<10 points), you can resubmit once after 24+ hours. HN allows this for Show HN posts that didn't get attention.

---

## Author Comment (post immediately after submission)

Post this as the first comment, within 1-2 minutes of submission:

```
Hi HN — I'm the author.

YoctoClaw is a fully autonomous coding agent — the same agentic loop as Claude Code
(prompt → LLM → tools → repeat) — in a single 180KB static binary. Written in Zig.
Zero dependencies.

Some context on why this exists:

Every coding agent I've used is 50–500MB. Claude Code pulls ~500 npm packages.
Cursor ships as a 500MB Electron app. But the actual agent logic — calling an LLM,
parsing tool calls, executing them, managing context — is tiny.

I wanted to know how tiny. The answer: 3,300 lines of Zig, 13 source files,
180KB compiled.

A few engineering decisions that made this possible:

- Hand-rolled JSON parser (500 lines) instead of std.json. Only handles the exact
  API shapes for Claude, OpenAI, and Ollama. No tree, no generality, no allocations.

- FNV-1a stuck-loop detection (128 bytes). If the LLM calls the same tool with the
  same input 3+ times, it gets a nudge. Critical for embedded where you can't afford
  runaway loops.

- Priority-based context truncation. When the context window fills, drops assistant
  text first (large, redundant), preserves tool results (small, high-info).

- Vtable transports: same binary works over HTTP (desktop), BLE (smart ring), or
  Serial (dev board). Feature flags at compile time.

The embedded angle started as a stretch goal but became the most interesting part.
The agent brain (conversation state, tool selection, context management) runs on-device.
A phone/laptop bridges it to the API and executes tools. Target hardware includes
the $3 ESP32-C3 and the nRF5340.

Current limitations I'm upfront about:
- JSON parser is flat (first-match extraction, works for Claude/OpenAI but not
  arbitrary JSON)
- Search is substring, not regex (regex engine would add ~10K lines)
- BLE transport has the protocol but needs platform SDK linking for real hardware
- No conversation persistence

It's MIT licensed. Happy to answer any questions about the design.
```

---

## Comment Response Playbook

### "It's a toy"
```
Fair question. It does work — here's a demo of it building a REST API: [link to demo].

39 unit tests, 9 integration tests, CI with binary size gate. But you're right
that it's not a Claude Code replacement. It's a minimal agent that proves the
core harness is simple. If you need IDE integration, cloud sync, or team
features, use Claude Code.
```

### "Why Zig?"
```
Zig gives us: native compilation with no runtime, comptime for feature flags,
manual memory control (critical for the arena allocator on embedded), and a
genuinely small standard library.

The equivalent in Rust would be ~3.4MB (ZeroClaw exists, it's 19x larger).
Go gets to ~8MB. Zig's combination of control and simplicity is uniquely
suited to this.

That said, C++, C#, and C ports are planned — each one gets its own launch.
```

### "But Claude Code has way more features"
```
Absolutely. Claude Code has IDE integration, extensions, cloud sync, team
collaboration, and dozens of tools. Those are genuinely valuable.

YoctoClaw's point is that the AGENT — the loop that makes it autonomous — is
3,300 lines. The other ~97,000 lines in Claude Code are platform, not harness.

Different products for different needs. YoctoClaw is for people who want a
minimal, understandable, portable agent — especially on embedded hardware.
```

### "Who needs a coding agent on a smart ring?"
```
Honestly? Maybe nobody, today. But:

1. The discipline of targeting embedded made the desktop binary better.
   Every allocation is intentional, every line justified.

2. Edge computing and air-gapped environments are real. CI/CD on constrained
   infra, IoT fleet management, classified environments.

3. "Who needs a computer in their pocket?" was a real question in 2006.

The embedded capability is real (BLE transport, arena allocator, target hardware).
Whether the use case materializes is an open question. But the desktop agent
is better because we asked it.
```

### "The LOC count seems low/suspicious"
```
The repo is public — `wc -l src/*.zig` gives you the exact number.

Breakdown: ~2,800 lines of core logic + ~500 lines of inline unit tests = ~3,300.

I'd encourage anyone to read any file. json.zig is the most interesting
(the hand-rolled parser). agent.zig is the core loop. tools.zig has all 6 tools.

If you find padding, file an issue. Seriously.
```

### "How does it compare to [specific tool]?"
```
We have a detailed comparison table in the README. The short version:

- vs Claude Code: 278x smaller binary, same core loop, no platform features
- vs Aider: 278x smaller, 0 deps vs 100, 3 providers vs 10+
- vs ZeroClaw (Rust): 19x smaller binary, both target minimalism
- vs OpenCode (Go): 83x smaller, YoctoClaw targets embedded

Each tool makes different tradeoffs. YoctoClaw optimizes for size and portability.
```

---

## HN Engagement Rules

1. **Reply to every comment in the first 3 hours.** This is the single most important factor for staying on the front page.

2. **Be technical, not defensive.** HN rewards deep technical answers. If someone asks about the JSON parser, explain FNV-1a hashing or arena allocation. Give them something to learn.

3. **Acknowledge limitations openly.** "No regex because a regex engine is 10K+ lines" gets respect. "It handles everything!" gets skepticism.

4. **Never astroturf.** Don't have friends upvote. Don't use multiple accounts. HN detects and penalizes this aggressively.

5. **Don't edit the title.** Once it's up, it's up. If mods change it, that's fine — they usually have good instincts.

6. **Share code, not marketing.** If someone asks "how does X work?", link to the specific file and line number. `json.zig:L42` is more compelling than a paragraph of explanation.

7. **If it doesn't hit the front page:** Wait 24+ hours and try once more with a different title variant. If that doesn't work either, the community has spoken — focus on other channels.
