# Contributing to KrillClaw

KrillClaw is 13 files and ~3,300 lines of Zig. You can read the entire codebase in an afternoon. We encourage you to do that before contributing.

## Quick Start

```bash
# Install Zig 0.13+ from https://ziglang.org/download/
git clone https://github.com/yoctoclaw/TinyDancer
cd TinyDancer/krillclaw

# Build
zig build

# Run tests (39 unit tests)
zig build test

# Build release binary
zig build -Doptimize=ReleaseSmall

# Check binary size
ls -la zig-out/bin/krillclaw

# Run integration tests
bash test/integration.sh
```

## Architecture Overview

```
src/
├── main.zig        # CLI + REPL (entry point)
├── agent.zig       # Agentic loop + stuck-detection
├── api.zig         # HTTP client (Claude/OpenAI/Ollama)
├── stream.zig      # SSE streaming parser
├── json.zig        # Hand-rolled JSON builder + extractor
├── tools.zig       # 6 tools (bash, read/write/edit, search, list)
├── context.zig     # Token estimation + truncation
├── config.zig      # Config: file → env → CLI
├── transport.zig   # Transport vtable + RPC
├── types.zig       # Core types
├── ble.zig         # BLE GATT transport
├── serial.zig      # UART/serial transport
└── arena.zig       # Fixed arena allocator (embedded)
```

## Guidelines

### Binary Size Matters

KrillClaw's identity is its size. Every PR that increases the release binary is scrutinized.

- **<1 KB increase:** Generally fine if the feature is valuable.
- **1-5 KB increase:** Needs justification in the PR description.
- **>5 KB increase:** Requires discussion before implementation. Open an issue first.

CI enforces a hard gate: the release binary must stay under 300KB.

### Zero Dependencies

KrillClaw has zero Zig dependencies. This is intentional and non-negotiable.

- No `build.zig.zon` package imports.
- No vendored third-party code.
- Use `std` library functions where they don't bloat the binary.
- If `std` adds too much (like `std.json`), write a minimal alternative.

### Code Style

- Match existing style. Read the file you're modifying before changing it.
- No unnecessary abstractions. Three similar lines > one premature helper.
- Comments explain *why*, not *what*. The code should be clear enough to explain itself.
- Keep functions short. If it doesn't fit on a screen, consider splitting.
- Error handling: return errors, don't panic. `try` everywhere, `catch` at boundaries.

### Testing

- New features need inline tests (`test "description" { ... }`).
- Tests go in the same file as the code they test.
- Run `zig build test` before submitting. All 39+ tests must pass.
- Integration tests in `test/integration.sh` for CLI-level behavior.

### Security

- No shell injection. `search` and `list_files` use pure Zig `std.fs` APIs.
- Escape all string fields in JSON/RPC builders.
- Cap output sizes (bash: 256KB, search: 100 matches, list: 200 files).
- If your change touches tool execution or transport, think about injection vectors.

## How to Contribute

### Good First Issues

Look for issues labeled `good-first-issue`. These are scoped, well-described, and designed for newcomers. They're also a great way to learn the codebase.

### Before You Start

1. Check existing issues and PRs — someone might already be working on it.
2. For non-trivial changes, open an issue first to discuss the approach.
3. For binary-size-sensitive changes (new features, new imports), discuss before coding.

### Pull Request Process

1. Fork and create a branch: `git checkout -b feat/your-feature`
2. Make your changes. Add tests.
3. Run `zig build test` — all tests must pass.
4. Run `zig build -Doptimize=ReleaseSmall` — check binary size.
5. Open a PR with:
   - What the change does (1-2 sentences)
   - Binary size impact (before/after `ls -la zig-out/bin/krillclaw`)
   - Test coverage (which tests cover the change)

### What Makes a Great PR

- **Small and focused.** One feature or fix per PR.
- **Tests included.** Inline tests for new logic.
- **Size-aware.** Binary size before/after in the description.
- **Well-scoped.** Don't refactor adjacent code unless it's broken.

## Reporting Bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md). Include:
- Zig version (`zig version`)
- OS and architecture
- Steps to reproduce
- Expected vs actual behavior
- Binary build flags (e.g., `-Dble=true`)

## Requesting Features

Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md). Include:
- Use case (what problem does this solve?)
- Estimated binary size impact
- Whether you'd be willing to implement it

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
