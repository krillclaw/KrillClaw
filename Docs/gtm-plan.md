# YoctoClaw — Go-To-Market Plan

## 1. Positioning & Messaging

### Core Positioning Statement

**YoctoClaw is the world's smallest fully autonomous coding agent — 180KB, zero dependencies, written in 3,300 lines of Zig — proving that the entire agent harness is a solved problem in under 4,000 lines of code.**

### Three Messaging Pillars

| Pillar | Core Claim | Proof Point |
|--------|-----------|-------------|
| **Radical Minimalism** | A full coding agent in 180KB | 278x smaller than Claude Code, 2,778x smaller than Cursor. Smaller than a JPEG. |
| **Embedded-First** | The only coding agent that runs on a $3 chip | BLE + Serial transports, fixed arena allocator, runs on ESP32-C3, nRF5340, smart rings |
| **Transparent Simplicity** | You can read the entire codebase in an hour | 3,300 LOC across 13 files. Zero dependencies. Every line earns its place. |

### Five Target Audience Segments

**Segment 1: Zig & Systems Developers**
- *Why they care:* Cool, well-architected Zig project. Zero deps. Comptime feature flags. Hand-rolled JSON parser. This is Zig the way Zig is meant to be written.
- *Message:* "A full coding agent in 3,300 lines of idiomatic Zig. No std.json. No runtime. Every byte earns its place."
- *Channels:* r/zig, Zig Discord, Zig monthly newsletter, HN, Ziggit

**Segment 2: Embedded & IoT Developers**
- *Why they care:* An AI agent that runs on MCU hardware. BLE transport. Serial transport. Fixed arena allocator. This is unprecedented.
- *Message:* "The first coding agent you can flash to an nRF5340. BLE transport, arena allocator, 50KB on-device footprint."
- *Channels:* Hackaday, r/embedded, embedded.fm podcast, EEVblog, Adafruit blog

**Segment 3: Privacy-Conscious Developers**
- *Why they care:* Ollama support means fully local AI coding — no API keys, no data leaving your machine. Static binary means no supply chain risk.
- *Message:* "YoctoClaw + Ollama = fully local AI coding. No API keys. No telemetry. No npm supply chain. One static binary."
- *Channels:* r/LocalLLaMA, r/privacy, AI Twitter (local LLM crowd), privacy-focused newsletters

**Segment 4: "Dependency Hell" Refugees**
- *Why they care:* Every developer has been burned by `npm install` pulling 500 packages or `pip install` breaking their system. Zero deps is the dream.
- *Message:* "Zero dependencies. One binary. No npm. No pip. No Docker. Just `zig build && ./yoctoclaw`."
- *Channels:* r/programming, HN, dev Twitter, Dev.to

**Segment 5: AI Agent Builders & Researchers**
- *Why they care:* YoctoClaw is the minimal reference implementation of an agentic loop. It's the best way to understand how coding agents actually work — all signal, no framework noise.
- *Message:* "Want to understand how coding agents work? Read 3,300 lines instead of 100,000. YoctoClaw is the minimal agentic loop."
- *Channels:* AI Twitter, r/MachineLearning, Simon Willison's blog, Latent Space podcast

### Competitor Framing

| Competitor | Frame |
|-----------|-------|
| **Claude Code** | "Same agentic loop, 278x larger binary. The difference is platform features (IDE, extensions, cloud sync) — not the agent itself." |
| **Cursor** | "2,778x larger. Most of that is Electron. The agent logic is a tiny fraction of the download." |
| **Aider** | "Great multi-provider support (10+ providers). But 50MB, 100 pip packages. YoctoClaw does 3 providers in 180KB with zero deps." |
| **OpenCode** | "Solid Go implementation, 15MB. But YoctoClaw is 83x smaller and targets hardware OpenCode can't touch." |
| **ZeroClaw** | "Rust implementation, 3.4MB. Closest competitor in the 'small agent' space. But Zig gets 19x smaller with zero deps." |

---

## 2. Launch Strategy

### Pre-Launch (2 weeks before)

**Week -2: Seed the narrative**
- [ ] Post to Zig Discord `#showcase` — "Working on something: AI coding agent in pure Zig, targeting <200KB binary. Anyone interested in BLE transport for embedded?" Gauge interest, don't reveal full scope.
- [ ] Tweet teaser from Accelerando AI account: binary size screenshot (`ls -la` showing 180KB), no context. "Coming soon."
- [ ] Create `good-first-issue` labels on 5-8 issues (see Section 5). These need to exist before launch day so newcomers have something to do.
- [ ] Prep all launch content (blog post, threads, Reddit posts, HN comment) — everything written and reviewed before launch day.

**Week -1: Build anticipation**
- [ ] Second Zig Discord post: architecture diagram + "13 files, 3,300 lines, zero dependencies" — link to private beta if anyone wants early access.
- [ ] DM 5-10 Zig community members with early access. Get at least 2-3 people to star/fork before launch (social proof).
- [ ] Tweet the comparison table (YoctoClaw vs Claude Code vs Cursor) without naming YoctoClaw — "What if a coding agent was this small?" Let people speculate.
- [ ] Identify and brief 3-5 influential accounts who might amplify (see outreach list below).

**Influencer/Amplifier Outreach List:**

| Person | Why | Platform | Approach |
|--------|-----|----------|----------|
| Andrew Kelley | Zig creator. A nod from him = Zig community adoption. | Twitter, Zig Discord | DM with early access, emphasize Zig-idiomatic design |
| Simon Willison | Covers AI tools obsessively. Will appreciate the minimalism angle. | Blog, Twitter | Email pitch: "coding agent in 180KB" one-liner |
| Mitchell Hashimoto | Zig enthusiast (Ghostty). Massive dev following. | Twitter | Tweet @ him on launch day with comparison table |
| Xe Iaso | Writes about systems programming + AI. | Blog, Fediverse | Email pitch, angle: "read the entire codebase in an hour" |
| ThePrimeagen | Content creator, loves systems languages, hates Electron bloat. | YouTube, Twitter | Send comparison chart, "your coding agent is 1000x too big" |
| Hackaday editors | Cover embedded projects. Smart ring angle is perfect for them. | Hackaday.com | Submit tip: "AI coding agent runs on smart ring via BLE" |
| Embedded.fm hosts | Podcast about embedded systems. BLE agent is novel content. | Podcast | Pitch guest spot or project feature |

### Launch Day

**Timing:** Tuesday or Wednesday, 9-10am ET (HN peak). Never launch on Friday or Monday.

**Sequence (strict order):**

1. **T-0:00** — Push all content live:
   - GitHub repo goes public (ensure README, CONTRIBUTING.md, issue templates are ready)
   - Blog post goes live at accelerando.ai/blog

2. **T-0:05** — HN submission
   - Title: `Show HN: YoctoClaw – A full coding agent in 3,300 lines of Zig (180KB binary)`
   - Immediately post author comment (see `Docs/hn-submission.md`)

3. **T-0:10** — Twitter/X launch thread
   - 5-tweet thread from @AccelerandoAI
   - Pin the thread

4. **T-0:30** — Reddit posts (staggered to avoid spam detection)
   - r/zig (most receptive audience first)
   - r/programming (15 min later)
   - r/LocalLLaMA (15 min later)
   - r/embedded (15 min later)

5. **T-1:00** — Dev.to cross-post of blog

6. **T-2:00** — Engage with every HN comment, Twitter reply, Reddit comment. Author presence = front page staying power.

### Post-Launch (Weeks 1-4)

**Week 1: Ride the wave**
- Respond to every GitHub issue within 4 hours
- Merge at least one external PR (even if trivial) — proves the project accepts contributions
- Post follow-up Twitter thread: technical deep-dive on JSON parser
- Share any noteworthy community reactions (retweets, blog mentions)

**Week 2: Deepen the narrative**
- Publish "Hand-rolled JSON in 500 lines" blog post
- Post to r/zig: deep-dive on the arena allocator design
- Twitter thread: embedded/BLE architecture
- Start "What should we build next?" GitHub Discussion

**Week 3: Expand reach**
- Publish "YoctoClaw vs Claude Code" comparison post
- Submit to Hackaday (embedded angle)
- Pitch embedded.fm podcast
- Twitter thread: Ollama/local angle for privacy crowd

**Week 4: Consolidate**
- Publish "Every coding agent ranked by binary size" comparison
- Release minor version with community-requested feature
- Monthly metrics review (see Section 7)
- Begin planning YoctoClaw C++ announcement (see Section 6)

---

## 3. Content Plan

### Launch Blog Post

**Title:** "Why We Built a Coding Agent in 3,300 Lines of Zig"

**Structure:**
1. The Observation — Every coding agent is 50-500MB. The actual logic is tiny.
2. The Experiment — What if we stripped everything to the core agentic loop?
3. The Architecture — 13 files, what each one does (with line counts)
4. The Results — 180KB, <10ms boot, 2MB RAM. Comparison table.
5. The Surprising Part — It works on embedded hardware. BLE, serial, smart rings.
6. What We Learned — The harness is simple. The complexity is platform, not agent.
7. Try It — One-liner install, MIT license, GitHub link.

*Full draft in `Docs/launch-blog-post.md`*

### Technical Deep-Dive Series (weeks 2-6)

| Post | Hook | Audience |
|------|------|----------|
| "Hand-Rolled JSON in 500 Lines" | Why we skipped std.json and what it taught us about Zig allocation | Zig devs, language nerds |
| "One Binary, Three Physical Layers" | Vtable transport abstraction: HTTP, BLE, Serial | Embedded devs, systems programmers |
| "Loop Detection in 128 Bytes" | FNV-1a hashing for stuck-agent detection on constrained hardware | AI researchers, embedded devs |
| "A Coding Agent on a Smart Ring" | BLE transport architecture — the ring thinks, the phone relays | Everyone (viral potential) |
| "Priority-Based Context Truncation" | When tokens run out, what do you keep? | AI agent builders |

### Video Content

| Video | Format | Priority |
|-------|--------|----------|
| "YoctoClaw solves a real coding task" | 2-min terminal recording (asciinema or screen capture) | **P0 — launch day** |
| "180KB vs 500MB: binary size comparison" | Visual bar chart animation | P1 — week 1 |
| "Building YoctoClaw from source in 1 second" | Terminal recording: git clone → zig build → run | P1 — week 1 |
| "YoctoClaw on nRF5340 over BLE" | Hardware demo video | P2 — week 3+ (needs hardware) |

### Comparison Content

- "YoctoClaw vs Claude Code: Same Job, 278x Smaller" — head-to-head across 15 dimensions
- "Every Coding Agent Ranked by Binary Size" — comprehensive landscape survey

*Full drafts in `Docs/comparison-content.md`*

---

## 4. Distribution Channels

### GitHub (Primary)

**Star acquisition strategy:**
- README optimized for scroll-stopping (comparison table above the fold)
- Topics/tags: `zig`, `ai-agent`, `coding-agent`, `llm`, `embedded`, `ble`, `cli`, `developer-tools`
- GitHub social preview image: comparison chart as image
- "Star this repo" CTA in every external post
- Release tags on launch day (v0.1.0) — appears in GitHub Explore

**Good-first-issues seeded before launch:**
- "Add `--version` flag" (trivial, great onboarding)
- "Add `--no-color` flag for piping output" (easy, practical)
- "Improve error message when API key is missing" (easy, user-facing)
- "Add JSON config file example to README" (docs, low barrier)
- "Add test for edit_file with non-existent file" (test writing, teaches codebase)

### Hacker News

- Title format: `Show HN:` prefix for first-time submissions
- Post at 9-10am ET Tuesday/Wednesday
- Author comment immediately: technical context, motivation, what's next
- Respond to every comment within the first 2 hours — this is what keeps posts on the front page
- Never be defensive about "it's a toy" — redirect to "try it and see"
- *Detailed strategy in `Docs/hn-submission.md`*

### Twitter/X

**Account:** @AccelerandoAI (or personal account of founder)

**Thread strategy:**
- Launch thread: 5 tweets (hook → table → embedded → technical → CTA)
- Follow-up threads: one per week for 4 weeks, each on a different angle
- Quote-tweet the Aakash Gupta "agent harness" post if timing aligns
- @ influential accounts on launch day (Mitchell Hashimoto, ThePrimeagen, Simon Willison)
- Use `#zig`, `#coding`, `#ai` hashtags sparingly (1-2 per thread)

**Engagement rules:**
- Reply to every comment in the first 6 hours
- Retweet anyone who builds something with YoctoClaw
- Share "I tried YoctoClaw" posts even if critical (shows confidence)

### Reddit

| Subreddit | Angle | Title Style |
|-----------|-------|-------------|
| r/zig | "Cool Zig project" — lead with idiomatic Zig, zero deps, comptime | "I built a full AI coding agent in 3,300 lines of Zig with zero dependencies" |
| r/programming | "Size is absurd" — lead with 180KB vs 500MB comparison | "What if a coding agent was 180KB instead of 500MB?" |
| r/LocalLLaMA | "Fully local" — lead with Ollama, privacy, static binary | "YoctoClaw: A 180KB coding agent that works with Claude, OpenAI, and Ollama" |
| r/embedded | "Agent on MCU" — lead with BLE, nRF5340, smart ring | "We built a coding agent that runs on an nRF5340 over BLE" |

**Reddit rules:**
- Follow each subreddit's self-promotion guidelines
- Posts should be informative, not just links
- Include technical details in the post body
- Respond to every comment
- *Full post bodies in `Docs/reddit-posts.md`*

### Zig Community

- **Zig Discord #showcase** — post on launch day with screenshots
- **Ziggit forum** — detailed technical post about design decisions
- **Zig monthly newsletter** — submit for inclusion (email zig newsletter maintainer)
- **Zig meetups** — offer to give a lightning talk (virtual or in-person)

### Embedded Community

- **Hackaday** — submit project tip (smart ring angle). Hackaday loves embedded + unusual projects.
- **embedded.fm podcast** — pitch a 15-min segment on "AI agents on constrained hardware"
- **EEVblog forums** — post in project showcase
- **Adafruit blog** — they feature cool embedded projects using common dev boards

### AI/ML Community

- **r/MachineLearning** — "minimal reference implementation of agentic loop" angle
- **AI Twitter** — quote-tweet relevant conversations about agent complexity
- **Simon Willison's blog** — email him directly. He covers every interesting AI tool.
- **Latent Space podcast** — pitch for "AI infrastructure" episode segment

### Dev Content Platforms

- **Dev.to** — cross-post launch blog
- **Hashnode** — cross-post with Zig tag
- **Lobste.rs** — submit (needs invite or existing member)

---

## 5. Community Building

### GitHub Discussions

Enable GitHub Discussions with these categories:
- **General** — introductions, questions, help
- **Ideas** — feature requests, design discussions
- **Show & Tell** — "I used YoctoClaw for X" showcase posts
- **Architecture** — deep technical discussions about design decisions

### Contributing Guide

*Full guide in `CONTRIBUTING.md`*

Key elements:
- "You can read the entire codebase in an hour" — encourage reading before contributing
- Clear build/test instructions
- Coding conventions (match existing style, no new deps, keep binary small)
- Binary size gate: PRs that increase binary size >5KB need justification
- Test requirements: new features need inline tests
- Issue labels: `good-first-issue`, `help-wanted`, `binary-size`, `embedded`, `provider`

### First-Issue Strategy

Seed 8-10 issues before launch, labeled `good-first-issue`:

| Issue | Difficulty | What It Teaches |
|-------|-----------|-----------------|
| Add `--version` flag | Trivial | CLI arg parsing in main.zig |
| Add `--no-color` output flag | Easy | Config system, output formatting |
| Better error on missing API key | Easy | Config loading, error messages |
| Add `.yoctoclaw.json` example | Docs | Config file format |
| Test: edit_file on non-existent file | Easy | Test writing, tools.zig |
| Test: search with binary file | Easy | Binary detection in tools.zig |
| Support `YOCTOCLAW_MAX_TURNS` env var | Medium | Agent loop, config precedence |
| Add token count to REPL prompt | Medium | Context tracking, REPL UI |

### Community Goals

| Milestone | 30 Days | 60 Days | 90 Days |
|-----------|---------|---------|---------|
| GitHub stars | 500 | 1,500 | 3,000 |
| Forks | 50 | 150 | 300 |
| Contributors | 5 | 15 | 30 |
| Open issues | 20 | 40 | 60 |
| Merged external PRs | 3 | 10 | 25 |
| Blog mentions | 3 | 8 | 15 |

### Champion Identification

Look for these early adopters and engage directly:
- People who open well-written issues or PRs
- Anyone who writes a blog post or tweet about YoctoClaw
- Embedded developers who try it on real hardware
- People who port features or build integrations

Offer them: early access to roadmap, direct Discord/DM channel, credit in release notes, "contributor" role in GitHub Discussions.

---

## 6. Expansion Roadmap

Each port gets its own launch moment — don't bundle them. Stagger by 4-6 weeks for sustained attention.

### YoctoClaw C++ (Launch +6 weeks)

**Angle:** "The fastest local coding agent. Direct llama.cpp integration. No Python. No API key needed."
- Target the local-LLM community hard
- C++ has only one competitor (llama-agent, ~150 stars, local-only)
- Integration with llama.cpp for true single-binary local AI coding
- HN title: "YoctoClaw C++: A coding agent with built-in llama.cpp (no API key needed)"

### YoctoClaw C# (Launch +12 weeks)

**Angle:** "The first CLI coding agent in C#. For the .NET ecosystem."
- C# has **zero** CLI coding agents — this is greenfield
- Target .NET developers, enterprise devs, Microsoft ecosystem
- Leverage MS Agent Framework, Semantic Kernel awareness
- HN title: "YoctoClaw C#: The first CLI coding agent for .NET"

### YoctoClaw C (Launch +18 weeks)

**Angle:** "True bare-metal. The coding agent that needs no OS."
- Pure C, no stdlib dependency option
- Target the "C is the only real language" crowd
- Smallest possible binary (target <100KB)
- Embedded-first, desktop-second
- HN title: "YoctoClaw C: A coding agent in <100KB of C with no stdlib"

### Port Launch Playbook (reusable for each)
1. Teaser tweet: "YoctoClaw is learning a new language..."
2. Pre-launch: seed in relevant community (r/cpp, r/dotnet, r/C_Programming)
3. Launch blog post: "Why we ported YoctoClaw to [language]"
4. HN Show submission
5. Reddit cross-posts
6. Comparison update: add new port to all comparison tables

---

## 7. Metrics & KPIs

### Week 1 Targets

| Metric | Target | Stretch | How to Track |
|--------|--------|---------|-------------|
| GitHub stars | 200 | 500 | GitHub API |
| HN front page | Yes | Top 10 | Manual / HN API |
| HN points | 100 | 300 | HN API |
| Twitter impressions | 50K | 200K | Twitter Analytics |
| Twitter thread engagement | 500 likes | 1,000 | Twitter Analytics |
| Reddit upvotes (total) | 200 | 500 | Reddit |
| Unique clones | 100 | 500 | GitHub Traffic |
| First external PR | 1 | 3 | GitHub |

### Month 1 Targets

| Metric | Target | Stretch |
|--------|--------|---------|
| GitHub stars | 500 | 2,000 |
| Contributors | 5 | 15 |
| Forks | 50 | 200 |
| Blog/media mentions | 3 | 10 |
| External integrations/ports | 0 | 1 |
| Ollama users (self-reported) | 10 | 50 |

### Tracking Plan

- **GitHub:** Use GitHub Insights (Traffic, Clones, Popular Content)
- **Twitter:** Twitter Analytics for impressions, engagement rate
- **HN:** Check placement and point count hourly on launch day
- **Reddit:** Track upvotes and comment count per post
- **Mentions:** Set up Google Alert for "YoctoClaw", monitor Twitter mentions
- **Weekly review:** Every Friday, review metrics and adjust content plan

---

## 8. "Agent Harnesses" Response

### The Thesis (Aakash Gupta)

> "The moat is your agent harness, not your model. Agent harnesses require hundreds of thousands of lines of code and thousands of engineer hours."

### The YoctoClaw Counter

**"What if your harness was 180KB?"**

Aakash is right that the harness matters. He's wrong about what makes a good harness. The complexity in Claude Code and Cursor isn't the agent loop — it's the platform: IDE integration, extension marketplace, collaboration, cloud sync, telemetry, A/B testing, billing. Strip all that away and the harness is 3,300 lines.

**Our messaging framework:**

1. **The harness IS simple.** YoctoClaw proves that the core agent loop — LLM calls, tool execution, context management, conversation state — fits in 3,300 lines and 180KB.

2. **The real moat is harness density.** Not how many lines you have, but how much capability per byte. YoctoClaw is the densest agent harness ever built.

3. **Platform ≠ harness.** The complexity in Claude Code is *platform* features (IDE, cloud, extensions). The agent harness itself is a solved problem. YoctoClaw is the proof.

**Deployment of this message:**

- Quote-tweet Aakash's post with the "What if your harness was 180KB?" angle
- Include in the launch blog post as a "what we learned" section
- Use in HN author comment: "We wanted to test the thesis that agent harnesses are inherently complex"
- Reference in comparison content: frame Claude Code's 100K LOC as "99% platform, 1% harness"

---

## 9. Risk Mitigation

### Objection: "It's just a toy"

**Response strategy:** Don't argue. Demonstrate.

- Launch with a demo video showing YoctoClaw completing a real task (e.g., "create a REST API with auth")
- Point to the test suite: 39 unit tests, 9 integration tests, CI pipeline with binary size gate
- Say: "Try it. `zig build && ./yoctoclaw 'fix the tests'`. It either works or it doesn't."
- Acknowledge limitations openly (no regex search, no persistence, flat JSON parser) — this builds credibility
- Frame as: "It's a minimal agent, not a minimal effort"

### Objection: "Zig is too niche"

**Response strategy:** Turn it into a feature, not a limitation.

- "Zig is why it's 180KB. Try getting there with Node.js."
- "You don't need to know Zig to use YoctoClaw. `zig build` is the only command."
- "The Zig compiler is a single binary download. No package manager needed."
- Point to the expansion roadmap: C++, C#, C ports coming. Zig is the proof-of-concept.
- Reference Ghostty (Mitchell Hashimoto) and Bun (Jarred Sumner) as Zig success stories

### Objection: "No one needs embedded agents"

**Response strategy:** Reframe the question.

- "No one needed a computer in their pocket until the iPhone."
- Point to real use cases: CI/CD on constrained infra, edge computing, IoT device management, air-gapped environments
- The embedded angle is marketing differentiation, not the core use case. Desktop usage is the primary value prop.
- "Even if you never run it on a smart ring, the discipline of targeting embedded hardware made the desktop binary better."

### Objection: "The LOC count is inflated/misleading"

**Response strategy:** Total transparency.

- The repo is public. Anyone can count.
- `wc -l src/*.zig` produces the exact number
- Breakdown: ~2,800 core logic + ~500 inline tests = ~3,300 total
- Invite skeptics to read it: "It's 13 files. Pick any one and read it. If you think it's padded, file an issue."

### Objection: "Why not just use Claude Code?"

**Response strategy:** Agree and expand.

- "You should! Claude Code is great. YoctoClaw exists to prove a point: the agent harness is simple."
- "If you want IDE integration, cloud sync, and team features — use Claude Code or Cursor."
- "If you want to understand how agents work, run on embedded, or avoid 500 npm packages — try YoctoClaw."
- Don't position as a replacement. Position as a reference implementation and an embedded option.

---

## 10. Timeline

### Pre-Launch (Week -2 to -1)

| Day | Action | Owner |
|-----|--------|-------|
| Mon W-2 | Finalize all launch content (blog, threads, Reddit, HN) | Marketing |
| Tue W-2 | Create good-first-issues (8-10 issues) | Engineering |
| Wed W-2 | Post teaser to Zig Discord #showcase | Marketing |
| Thu W-2 | Record demo video (asciinema terminal recording) | Engineering |
| Fri W-2 | DM 5 Zig community members for early access | Marketing |
| Mon W-1 | Tweet teaser: binary size screenshot, no context | Marketing |
| Tue W-1 | Send pitch emails to Simon Willison, Hackaday, embedded.fm | Marketing |
| Wed W-1 | Post second Zig Discord teaser: architecture diagram | Marketing |
| Thu W-1 | Tweet comparison table without naming YoctoClaw | Marketing |
| Fri W-1 | Final review of all launch materials. Staging check. | All |

### Launch Week (Week 0)

| Day | Action |
|-----|--------|
| **Tue (Launch Day)** | 9am ET: Repo public + blog live. 9:05: HN submission + author comment. 9:10: Twitter thread. 9:30-10:30: Reddit posts (staggered). 10:00: Dev.to cross-post. All day: respond to every comment. |
| Wed | Respond to all overnight comments. Share best reactions. Handle incoming issues/PRs. |
| Thu | Follow-up Twitter thread: JSON parser deep-dive. Respond to late Reddit/HN comments. |
| Fri | Weekly metrics review. Merge first external PR if possible. Plan week 2 content. |

### Post-Launch (Weeks 1-4)

| Week | Content | Community | Outreach |
|------|---------|-----------|----------|
| **Week 1** | Twitter thread: JSON parser deep-dive | Respond to all issues within 4hrs. Merge first PR. | Share notable reactions. |
| **Week 2** | Blog: "Hand-Rolled JSON in 500 Lines". Reddit r/zig: arena allocator post. Twitter: embedded/BLE thread. | Start "What should we build next?" Discussion. | Pitch embedded.fm podcast. |
| **Week 3** | Blog: "YoctoClaw vs Claude Code". Twitter: Ollama/privacy thread. | Release minor version with community feature. | Submit to Hackaday. |
| **Week 4** | Blog: "Every Coding Agent Ranked by Size". | Monthly metrics review. Contributor spotlight. | Begin YoctoClaw C++ teaser campaign. |

### Months 2-3

| Month | Focus |
|-------|-------|
| **Month 2** | Technical deep-dive content (vtable transports, loop detection, context truncation). YoctoClaw C++ development begins. Community growth: aim for 15 contributors. |
| **Month 3** | YoctoClaw C++ launch (own launch cycle). Hardware demo video if available. Conference talk submissions (Strange Loop, Handmade Seattle, Zig meetups). Aim for 3,000 stars. |

---

## Appendix: Quick Reference

### One-Liners (for bios, tweets, descriptions)

- "The world's smallest coding agent. 180KB. Zero deps. Written in Zig."
- "A full coding agent in a binary smaller than a JPEG."
- "3,300 lines of Zig. Claude, OpenAI, Ollama. One binary."
- "The coding agent that runs on a $3 chip."

### Hashtags
`#zig` `#ziglang` `#coding` `#ai` `#llm` `#embedded` `#iot` `#opensource`

### Key URLs
- GitHub: github.com/matusjAGI/TinyDancer
- Website: yoctoclaw.dev (TBD)
- Blog: accelerando.ai/blog (TBD)

### Brand Rules
- Project name: **YoctoClaw** (one word, capital Y, capital C)
- Repo name: TinyDancer (historical, don't rename)
- Company: Accelerando AI
- License: MIT
- Never say "revolutionary" or "game-changing" — let the numbers speak
