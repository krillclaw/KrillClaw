<p align="center">
  <a href="https://yoctoclaw.github.io">
    <img src="https://yoctoclaw.github.io/krillclaw-mascot.png" alt="KrillClaw mascot — a kawaii coral shrimp" width="200">
  </a>
</p>

<h1 align="center">KrillClaw™</h1>

<p align="center">
  <strong>The smallest AI agent runtime for edge devices.</strong><br>
  180KB · Zero dependencies · No OS required · Any LLM provider<br>
  Runs on a $3 ESP32. Written in Zig.
</p>

<p align="center">
  <a href="https://yoctoclaw.github.io">Website</a> ·
  <a href="https://yoctoclaw.github.io/#waitlist">Get a Device</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#use-cases">Use Cases</a>
</p>

---

## Why?

Every AI agent runtime is a 200MB Node.js bundle. The actual logic — "call LLM, execute tools, loop" — is ~3,500 lines of Zig and a **180KB binary**. KrillClaw proves that every device can have an AI brain.

**Upgrade the brain, not the machine.**

## How It Compares

| | KrillClaw™ | MimiClaw | PicoClaw | OpenClaw |
|---|---|---|---|---|
| **Language** | Zig | C | Go | Node.js |
| **Binary size** | **180 KB** | ~2 MB | ~8 MB | ~200 MB |
| **RAM usage** | **2 MB** | ~512 KB* | ~10 MB | ~200 MB |
| **Source** | ~3,500 LOC | ~7K LOC | ? | ~40K LOC |
| **Dependencies** | **0** | ESP-IDF | Go stdlib | ~108 npm |
| **Target hardware** | $3 ESP32+ | $5 ESP32-S3 | $10 LicheeRV | Pi / VPS / Mac |
| **Needs OS?** | No | No | Linux | Linux / macOS |
| **Memory safety** | Yes (Zig) | No (C) | Yes (Go GC) | Yes (JS) |
| **LLM providers** | Any compatible | Claude + OpenAI | ? | Multi |
| **BLE transport** | Yes | No | No | No |
| **License** | MIT | MIT | MIT | MIT |

## Quick Start

```bash
# Install Zig 0.13+ from https://ziglang.org/download/

# Clone and build
git clone https://github.com/yoctoclaw/TinyDancer
cd TinyDancer
zig build -Doptimize=ReleaseSmall

# Set your API key (any OpenAI-compatible provider works)
export ANTHROPIC_API_KEY=sk-ant-...

# Run
./zig-out/bin/krillclaw "read the temperature and adjust the fan"

# Or use any other provider
export OPENAI_API_KEY=sk-...
./zig-out/bin/krillclaw --provider openai -m gpt-4o "monitor sensors"

# Local with Ollama
./zig-out/bin/krillclaw --provider ollama -m llama3 "explain this code"
```

## Profiles

Compile-time profiles select different tool sets. Only selected code is compiled — zero runtime overhead.

```bash
# Coding agent (default) — bash, read/write/edit files, search
zig build -Dprofile=coding -Doptimize=ReleaseSmall

# IoT agent — MQTT, HTTP, key-value store, device info
zig build -Dprofile=iot -Doptimize=ReleaseSmall

# Robotics agent — motor control, e-stop, telemetry
zig build -Dprofile=robotics -Doptimize=ReleaseSmall
```

| Profile | Tools | Binary Size |
|---------|-------|-------------|
| **coding** | bash, read/write/edit_file, search, list_files, apply_patch | ~180 KB |
| **iot** | publish_mqtt, subscribe_mqtt, http_request, kv_get/set, device_info | ~150 KB |
| **robotics** | robot_cmd (pose/velocity/gripper), estop, telemetry_snapshot | ~160 KB |

## Use Cases

When every device has an AI brain and WiFi, ordinary things become extraordinary.

### 🏠 Smart Fridge That Manages Groceries
A $3 ESP32 inside your fridge watches what gets consumed, notices you're low on staples, checks your shopping history, and pings you: "You tried that new yogurt last week but didn't reorder — want to go back to your usual, or give it another shot?"

### 🏠 Garage Door That Sees You Coming
KrillClaw on your garage monitors via a security camera. It sees you approaching with hands full, recognizes you, and opens the door automatically — no fumbling for a remote.

### 🌱 Greenhouse That Farms Itself
A KrillClaw node reads soil moisture, temperature, and the 5-day forecast. It recognizes the tomatoes are in flowering stage and adjusts irrigation accordingly. Weekly report: "Tomatoes on track for harvest in ~12 days. Reduced watering 15%."

### 🏭 CNC Machine That Predicts Failures
Vibration pattern changes subtly. KrillClaw cross-references the maintenance log and messages the supervisor: "Spindle vibration up 12% since Monday — similar to the pattern before the last bearing replacement. Recommend inspection within 48 hours."

### 🤖 Bionic Hand That Downloads Skills
A prosthetic hand with KrillClaw embedded. Picking up chopsticks? It loads a precision-grip pattern. Need surgical-assist mode? Steady hands, guided movements, zero tremor. Same hardware, infinite skills.

### 🤖 3D Printer That Fixes Its Own Failures
Layer adhesion drops on hour 6 of a 10-hour print. KrillClaw reads the temperature sensor, checks filament spool weight, and adjusts flow rate mid-print. You wake up to a perfect part instead of spaghetti.

### 🧸 AI Toys That Learn and Grow
A stuffed animal with a KrillClaw chip. It listens, responds, remembers your child's favorite stories, and adapts its personality over time. No cloud dependency for basic interactions — the agent runs locally.

### 🚗 OBD-II Fleet Intelligence
Plug a $3 ESP32 into any vehicle's OBD-II port. KrillClaw reads engine codes, monitors fuel efficiency trends, and texts you: "Fuel economy dropped 8% this month — likely the air filter based on mileage. $12 part, 5-minute swap." A fleet of 50 vehicles, each with a $3 brain.

> Every example runs on a $3-5 chip over WiFi. The intelligence lives in the cloud. The agency lives on the device.

## Retrofit Anything

You already own incredible hardware. The electronics inside just never had a brain.

- **Your 2018 car** → plug a $3 chip into OBD-II → predictive maintenance + efficiency coaching
- **Your exercise bike** → clip on a sensor node → real-time adaptive coaching
- **Your $50K CNC** → wire to vibration sensor → predictive maintenance without a $20K/year platform
- **Your "dumb" appliances** → $20 in chips → a house with a nervous system

**Every device you own is an upgrade away. Not a replacement away.**

## Supported LLM Providers

Works with any OpenAI-compatible API endpoint — 27+ providers and counting.

**Tier 1 — Direct API**
OpenAI · Anthropic · Mistral · Groq · DeepSeek · Cohere · Cerebras

**Tier 2 — Cloud Platforms**
Azure OpenAI · AWS Bedrock · Google Vertex AI

**Tier 3 — Aggregators & Routers**
OpenRouter · SiliconFlow · Hugging Face Inference · DeepInfra

**Tier 4 — Self-Hosted**
Ollama · vLLM · LiteLLM · LocalAI · llama.cpp · text-generation-webui · Jan · LM Studio · GPT4All

> Any endpoint that speaks the OpenAI chat completions format works. Set `KRILLCLAW_BASE_URL` and go.

## Architecture

16 Zig files. ~3,500 lines. The entire runtime.

```
src/
├── main.zig          # CLI, REPL, entry point                    (152 lines)
├── agent.zig         # Agent loop + stuck-loop detection         (250 lines)
├── api.zig           # Multi-provider HTTP client                (329 lines)
├── stream.zig        # SSE streaming parser                      (344 lines)
├── json.zig          # Hand-rolled JSON builder + extractor      (500 lines)
├── tools.zig         # Tool dispatcher — comptime profiles       (140 lines)
├── tools_coding.zig  # Coding profile: 7 tools                  (280 lines)
├── tools_iot.zig     # IoT profile: 6 bridge tools               (95 lines)
├── tools_robotics.zig # Robotics profile: 3 tools               (155 lines)
├── context.zig       # Token estimation + truncation             (225 lines)
├── config.zig        # Config: file → env → CLI                  (184 lines)
├── transport.zig     # Abstract vtable transport                 (129 lines)
├── types.zig         # Core types                                (194 lines)
├── ble.zig           # BLE GATT transport                        (159 lines)
├── serial.zig        # UART/serial transport                     (142 lines)
└── arena.zig         # Fixed arena allocator for embedded        (175 lines)
```

## Target Hardware

| Device | Cost | SoC | Notes |
|--------|------|-----|-------|
| ESP32-C3 | $3 | RISC-V | WiFi + BLE |
| Raspberry Pi Pico W | $6 | RP2040 | WiFi + BLE |
| Milk-V Duo | $8 | RISC-V | Linux capable |
| Colmi R02 Ring | $20 | BlueX RF03 | Smart ring |
| nRF5340-DK | $50 | nRF5340 | BLE 5.3, dual-core |
| Flipper Zero | $15 | STM32 | Sub-GHz, NFC, BLE |

## Build & Embedded

```bash
# Release build
zig build -Doptimize=ReleaseSmall

# With BLE support
zig build -Dble=true -Doptimize=ReleaseSmall

# With serial support
zig build -Dserial=true -Doptimize=ReleaseSmall

# Freestanding (bare-metal MCUs)
zig build -Dembedded=true -Dtarget=thumb-none-eabi -Doptimize=ReleaseSmall

# Run tests (39 unit tests)
zig build test
```

## Transport Layers

| Transport | Use Case | Status |
|-----------|----------|--------|
| **HTTP** | Desktop — direct HTTPS to API | Stable |
| **BLE** | Embedded — GATT protocol + desktop simulation | Experimental |
| **Serial** | Dev boards — UART to host machine | Experimental |

## Testing

- **39 inline unit tests** covering JSON, SSE streaming, arena allocation, context truncation, tool execution, and glob matching
- **9 integration tests** in `test/integration.sh`
- **CI pipeline** with binary size gate (<300KB)
- **Security tests** for injection attempts

See [TESTING.md](TESTING.md) for details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions, code style, and PR process.

## License

MIT — see [LICENSE](LICENSE).

> **Note:** License is under review. We are evaluating Fair Source / BSL options for future releases.

## Links

- 🌐 [Website](https://yoctoclaw.github.io)
- 🦐 [Get a Pre-Flashed Device](https://yoctoclaw.github.io/#waitlist)
- 🏢 [Accelerando AI](https://accelerando.ai) ([@AccelerandoAI](https://x.com/AccelerandoAI))

---

<p align="center">
  <em>Every device gets an AI brain.</em><br>
  Built by <a href="https://accelerando.ai">Accelerando AI</a>
</p>
