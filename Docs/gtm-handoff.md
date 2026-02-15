# YoctoClaw GTM (Go-To-Market) Marketing Plan — Handoff Brief

## Context for New Claude Code Instance

You are picking up a project called **YoctoClaw** — the world's smallest AI coding agent, written in Zig. Your job is to create a comprehensive GTM marketing plan for its public launch.

### What is YoctoClaw?

A fully autonomous AI coding agent in a single 180KB binary. Zero dependencies. Written in ~3,300 lines of Zig. Supports Claude, OpenAI, and Ollama. Has 6 tools (bash, read_file, write_file, edit_file, search, list_files). Can run on embedded hardware via BLE/Serial transports — including smart rings and $3 microcontrollers.

### Key differentiators
- **180KB binary** — 1000x smaller than Claude Code (~50MB), Cursor (~500MB)
- **~2 MB RAM** — vs 200MB+ for Claude Code
- **Zero dependencies** — no npm, no pip, no Docker
- **3 providers** — Claude, OpenAI, Ollama (local)
- **BLE + Serial transports** — runs on embedded hardware (nRF5340, ESP32-C3, smart rings)
- **Written in Zig** — zero runtime, no GC, compiles in ~1 sec
- **3,300 LOC total** — you can read the entire codebase in an hour
- **39 unit tests + CI** — production-quality, not a toy

### Competitive landscape

| Agent | Language | Binary | RAM | Source |
|-------|----------|--------|-----|--------|
| **YoctoClaw** | **Zig** | **~180 KB** | **~2 MB** | **~3,300 LOC** |
| PicoClaw Go | Go | ~8 MB | ~10 MB | ~5K LOC |
| ZeroClaw | Rust | ~3.4 MB | ~15 MB | ~3K LOC |
| MimiClaw | C | ESP32-S3 | 8 MB PSRAM | N/A |
| Claude Code | TypeScript | ~50 MB | ~200 MB | ~100K LOC |
| Aider | Python | ~50 MB | ~150 MB | ~30K LOC |
| OpenCode | Go | ~15 MB | ~20 MB | ~10K LOC |

**No existing agent in C++ or C#.** C++ has one local-only competitor (llama-agent, ~150 stars). C# has zero CLI coding agents despite rich framework support (MS Agent Framework, Semantic Kernel). These are expansion opportunities.

### Files to reference
- `README.md` — comprehensive project docs, feature table, architecture
- `WEBSITE.md` — existing marketing copy, tweet drafts, comparison tables, HN titles
- `src/` — all 13 Zig source files
- `bridge/bridge/bridge.py` — Python bridge for BLE/Serial

---

## Your Assignment: Create the GTM Marketing Plan

Build a comprehensive go-to-market plan covering all the sections below. Write it as a new file: `Docs/gtm-plan.md`.

### 1. Positioning & Messaging
- Core positioning statement (one sentence)
- Three messaging pillars (size, embedded, simplicity)
- Target audience segments:
  - Zig/systems developers
  - Embedded/IoT developers
  - Privacy-conscious developers (Ollama local)
  - "Dependency hell" refugees
  - AI agent builders / researchers
- Competitor positioning (how we frame against Claude Code, Aider, OpenClaw, ZeroClaw)

### 2. Launch Strategy
- Pre-launch (1-2 weeks before):
  - Teaser content plan
  - Community seeding (Zig Discord, r/zig, embedded forums)
  - Influencer outreach list (who in the Zig/AI/embedded world should know)
- Launch day:
  - Hacker News submission strategy (title, timing, comment plan)
  - Twitter/X thread (use drafts from WEBSITE.md as starting point, adapt for YoctoClaw)
  - Reddit posts (r/zig, r/programming, r/LocalLLaMA, r/embedded)
  - Dev.to / blog post
- Post-launch (week 1-4):
  - Response/engagement plan
  - Follow-up content cadence

### 3. Content Plan
- Launch blog post outline ("Why we built a coding agent in 3,300 lines of Zig")
- Technical deep-dive posts:
  - "Hand-rolled JSON in 500 lines: why we skipped std.json"
  - "Vtable transports: one binary, three physical layers"
  - "FNV-1a loop detection in 128 bytes"
  - "A coding agent on a smart ring: BLE transport architecture"
- Video content:
  - Demo video: YoctoClaw solving a real coding task
  - Binary size comparison visualization
  - Embedded demo: YoctoClaw on nRF5340 over BLE
- Comparison content:
  - "YoctoClaw vs Claude Code: 1000x size difference"
  - "Every coding agent ranked by binary size"

### 4. Distribution Channels
- GitHub (star acquisition strategy, README optimization, topics/tags)
- Hacker News (submission strategy, comment playbook)
- Twitter/X (thread strategy, engagement plan, who to @)
- Reddit (subreddit-specific messaging)
- Zig community (Discord, forum, Zig monthly newsletter)
- Embedded community (Hackaday, embedded.fm, EEVblog)
- AI/ML community (r/LocalLLaMA, AI Twitter, Simon Willison's blog)
- Dev.to / Hashnode / Medium
- YouTube (demo videos, technical walkthroughs)
- Podcasts (Zig-adjacent, embedded-focused, AI-focused)

### 5. Community Building
- GitHub Discussions setup
- Contributing guide
- First-issue labeling strategy
- Community goals (stars, forks, contributors at 30/60/90 days)
- Ambassador/champion identification

### 6. Expansion Roadmap (Marketing Angles)
- YoctoClaw C++ (local-first, llama.cpp integration)
- YoctoClaw C# (.NET, first CLI coding agent in C#)
- YoctoClaw C (bare-metal, true MCU agent)
- Each expansion gets its own launch moment

### 7. Metrics & KPIs
- Week 1 targets: GitHub stars, HN ranking, Twitter impressions
- Month 1 targets: contributors, forks, real user reports
- Tracking plan (how to measure)

### 8. Response to "Agent Harnesses" Thesis
- Frame YoctoClaw as proof that the "harness" is simple
- Messaging: "The real moat is harness density, not harness size"
- Use the Aakash Gupta angle (see WEBSITE.md for existing copy)

### 9. Risk Mitigation
- "It's just a toy" objection — response strategy
- "Zig is too niche" objection — response strategy
- "No one needs embedded agents" objection — response strategy
- "The LOC count is inflated" — verification strategy (invite readers to count)

### 10. Timeline
- Detailed week-by-week launch calendar
- Content production schedule
- Key milestones and decision points

---

## Tone & Style Guidelines
- Technical but accessible — write for developers, not marketers
- Bold claims backed by verifiable numbers (binary size, LOC, etc.)
- No hype — let the numbers speak. "180KB" is more powerful than "revolutionary"
- Use the "smaller than a JPEG" angle — it's memorable and true
- Embrace the Zig community aesthetic: practical, minimal, no BS
