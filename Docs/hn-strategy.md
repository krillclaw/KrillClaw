# Hacker News Launch Strategy — YoctoClaw

## Title Options

### 1. "Show HN: YoctoClaw – A full coding agent in ~3,500 lines of Zig (180KB binary)"
**Reasoning:** Combines Show HN format with the two most compelling numbers. "Full coding agent" sets expectations. "~3,500 lines" invites verification. "180KB" is the hook.
**Risk:** Slightly long, but within HN title limits (80 chars). ✅ 74 chars.
**Rating: ★★★★★** — Best all-around option.

### 2. "Show HN: A coding agent smaller than a JPEG, written in Zig"
**Reasoning:** The "smaller than a JPEG" angle is memorable and shareable. Provokes curiosity.
**Risk:** Slightly clickbait-y for HN. May attract "but can it actually do anything?" skepticism.
**Rating: ★★★★☆**

### 3. "Show HN: YoctoClaw – Coding agent in Zig that runs on a $3 ESP32"
**Reasoning:** The embedded angle is unique. No other agent does this. Targets the HW/embedded crowd.
**Risk:** Narrow appeal. The general HN audience cares more about the coding agent part than the embedded part.
**Rating: ★★★☆☆**

### 4. "Your coding agent is 1,000x too big"
**Reasoning:** Provocative. Challenges the status quo. Classic HN engagement bait.
**Risk:** No Show HN prefix means it won't get Show HN queue treatment. Lacks project name for discoverability.
**Rating: ★★★☆☆**

### 5. "Show HN: YoctoClaw – Zero-dependency Zig coding agent (Claude, OpenAI, Ollama)"
**Reasoning:** Emphasizes zero deps (HN loves this) and multi-provider support. Practical angle.
**Risk:** Less dramatic. Doesn't communicate the size story.
**Rating: ★★★☆☆**

**Recommendation: Go with #1.** It's factual, verifiable, and hits the two strongest hooks (LOC count and binary size).

## Optimal Posting Time

- **Best:** Tuesday–Thursday, 8:00–9:00 AM ET (13:00–14:00 UTC)
- **Second best:** Monday 8:00–9:00 AM ET
- **Avoid:** Weekends, Friday afternoons, holidays
- **For a Monday launch (Feb 16):** Post at **8:00 AM ET / 13:00 UTC / 13:00 WET**

Reasoning: HN traffic peaks during US work hours. Early morning ET catches the East Coast morning + West Coast pre-work browsing. Tuesday-Thursday have highest engagement, but Monday works well for launches since there's pent-up weekend demand for interesting content.

## Comment Playbook

### First Comment (post immediately after submission)

Post a detailed first comment explaining the project. This is critical for HN — it sets the tone and preempts objections.

```
Hi HN, I built YoctoClaw because I wanted to understand what a coding agent actually is at its core.

The answer: it's surprisingly simple. Call LLM, parse response, execute tools, loop. The complexity in existing agents (Claude Code ~100K LOC, Aider ~30K LOC) comes from platform features, not the agent loop.

YoctoClaw strips it down to the essentials:
- 16 Zig source files, ~3,500 lines total (including tests)
- Coding profile: 7 tools (bash, read/write/edit files, search, list_files, apply_patch)
- IoT/Robotics profiles: swappable tool sets for MQTT/HTTP and robot control
- 3 providers: Claude, OpenAI, Ollama (local)
- SSE streaming, context window management, stuck-loop detection
- 180KB binary, ~2MB RAM, zero dependencies

The embedded angle (BLE/serial transports) was the original motivation — I wanted a coding agent that could run on microcontrollers. The desktop version turned out to be useful on its own.

Architecture walkthrough in the README. Happy to answer questions about any design decision.
```

### Anticipated Questions & Responses

**"It's just a toy / It can't do real work"**
> Fair question. YoctoClaw's coding profile has 7 core tools including bash, read/write/edit files, search, list_files, and apply_patch. The agent loop is functionally identical to Claude Code — call LLM, execute tools, loop until done. What it doesn't have: IDE integration, MCP, multi-file diffs, approval workflows. It's a CLI coding agent, not an IDE.

**"Why not just use Claude Code?"**
> If Claude Code works for you, use it. YoctoClaw exists for three cases: (1) embedded/IoT targets where 50MB won't fit, (2) environments where you want zero dependencies, (3) people who want to understand how coding agents work by reading 3,317 lines instead of 100K.

**"Zig is too niche"**
> That's why we're also building YoctoClaw in Go (already done, 8MB), and plan C++ and C# versions. Zig was chosen for the minimum-size version because it produces the smallest native binaries with zero runtime.

**"The JSON parser is fragile"**
> It's intentionally simple — extractString finds the first matching key at any depth. This works for Claude/OpenAI/Ollama API responses where key names are unambiguous. We chose this tradeoff explicitly: 500 lines vs pulling in a full JSON library. It's documented in Known Limitations.

**"BLE on a smart ring is vaporware"**
> The BLE transport protocol and GATT service UUIDs are implemented. Desktop simulation works via Unix sockets. Real hardware integration requires the platform BLE SDK (e.g., Nordic SoftDevice). The README is transparent about this — see the "Note on BLE/embedded" section.

**"How is this different from ZeroClaw / PicoClaw?"**
> ZeroClaw (Rust): 3.4MB, ~3K LOC — excellent but 19x larger binary. YoctoClaw Go: 8MB, ~4K LOC, 50 deps — simpler but bigger. YoctoClaw Zig is the minimum: 180KB, ~3.5K LOC, 0 deps. Different tools for different needs.

### Engagement Strategy

1. **Respond to every substantive comment** in the first 2 hours
2. **Be humble about limitations** — HN respects honesty more than hype
3. **Link to specific source files** when discussing architecture decisions
4. **Don't argue with trolls** — one polite response, then disengage
5. **Upvote good questions** even if critical
6. **If it hits front page:** post a follow-up comment with benchmarks or a demo video link
