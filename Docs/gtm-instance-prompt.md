# YoctoClaw GTM Marketing Plan — New Instance Prompt

Copy everything below this line and paste into a new Claude Code instance.

---

## YoctoClaw GTM Marketing Plan — New Instance Prompt

You are creating a comprehensive Go-To-Market marketing plan for **YoctoClaw**, the world's smallest AI coding agent.

### Project Context

YoctoClaw is a fully autonomous AI coding agent written in **3,317 lines of Zig**. Zero dependencies. One binary (~180KB). Supports Claude, OpenAI, and Ollama. Has 6 tools (bash, read_file, write_file, edit_file, search, list_files). Can run on embedded hardware via BLE/Serial transports — including smart rings and $3 microcontrollers.

The project lives at the root of the TinyDancer repository (https://github.com/matusjAGI/TinyDancer).

### Key Files to Read First

1. `README.md` — Full technical documentation, feature tables, architecture, comparisons
2. `WEBSITE.md` — Existing marketing copy, tweet drafts, HN titles, comparison tables, selling points
3. `Docs/gtm-handoff.md` — Detailed brief with the 10-section plan outline you need to fill in

### Key Differentiators

- **180KB binary** — 1000x smaller than Claude Code (~50MB), Cursor (~500MB)
- **~2 MB RAM** — vs 200MB+ for Claude Code
- **Zero dependencies** — no npm, no pip, no Docker
- **3 providers** — Claude, OpenAI, Ollama (local)
- **BLE + Serial transports** — runs on embedded hardware (nRF5340, ESP32-C3, Colmi R02 smart ring)
- **Written in Zig** — zero runtime, no GC, compiles in ~1 sec
- **3,317 LOC total** — you can read the entire codebase in an hour
- **39 unit tests + CI** — production-quality, not a toy

### Competitive Landscape

| Agent | Language | Binary | RAM | Source |
|-------|----------|--------|-----|--------|
| **YoctoClaw** | **Zig** | **~180 KB** | **~2 MB** | **~3,300 LOC** |
| PicoClaw Go | Go | ~8 MB | ~10 MB | ~5K LOC |
| ZeroClaw | Rust | ~3.4 MB | ~15 MB | ~3K LOC |
| MimiClaw | C | ESP32-S3 only | 8 MB PSRAM | N/A |
| llama-agent | C++ | single binary | N/A | ~150 stars, local-only |
| Claude Code | TypeScript | ~50 MB | ~200 MB | ~100K LOC |
| Aider | Python | ~50 MB | ~150 MB | ~30K LOC |
| OpenCode | Go | ~15 MB | ~20 MB | ~10K LOC |

**C# has zero CLI coding agents.** C++ has one local-only competitor (llama-agent). C has only MimiClaw (embedded IoT, not desktop). These are future expansion opportunities.

### Your Task

Read `Docs/gtm-handoff.md` for the full 10-section outline, then create `Docs/gtm-plan.md` with the complete marketing plan covering:

1. **Positioning & Messaging** — core statement, 3 pillars, 5 audience segments, competitor framing
2. **Launch Strategy** — pre-launch seeding, launch day (HN, Twitter, Reddit), post-launch cadence
3. **Content Plan** — blog posts, technical deep-dives, videos, comparison content
4. **Distribution Channels** — GitHub, HN, Twitter/X, Reddit, Zig community, embedded community, AI/ML community, podcasts
5. **Community Building** — GitHub Discussions, contributing guide, first-issue strategy, 30/60/90 day goals
6. **Expansion Roadmap** — YoctoClaw C++, YoctoClaw C#, YoctoClaw C (each gets its own launch moment)
7. **Metrics & KPIs** — week 1 targets, month 1 targets, tracking plan
8. **"Agent Harnesses" Response** — frame against Aakash Gupta's thesis (see WEBSITE.md)
9. **Risk Mitigation** — "it's a toy", "Zig is niche", "no one needs embedded agents" objections
10. **Timeline** — week-by-week launch calendar

### Tone Guidelines

- Technical but accessible — write for developers, not marketers
- Bold claims backed by verifiable numbers (binary size, LOC count)
- No hype — let the numbers speak. "180KB" is more powerful than "revolutionary"
- Use the "smaller than a JPEG" angle — memorable and true
- Embrace the Zig community aesthetic: practical, minimal, no BS

### Output

Write the complete plan to `Docs/gtm-plan.md`, then commit and push to the current branch.
