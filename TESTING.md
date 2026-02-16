# KrillClaw / YoctoClaw Testing Guide

## Quick Start

```bash
# Run all tests locally
zig build test

# Build for size check
zig build -Doptimize=ReleaseSmall
ls -la zig-out/bin/yoctoclaw
```

## What CI Checks

Our GitHub Actions CI (`.github/workflows/ci.yml`) runs 5 jobs on every push and PR:

| Job | What it does | Fails on |
|-----|-------------|----------|
| **Unit Tests** | `zig build test` with Zig 0.13 + 0.15 | Any test failure (strict on 0.15) |
| **Cross-Compilation** | Builds for aarch64, arm, riscv64, x86_64, native | Compilation failure |
| **QEMU Smoke Tests** | Runs cross-compiled binaries via QEMU user-mode | N/A (reporting only) |
| **Binary Size Gate** | Compares Zig 0.13 vs 0.15 binary sizes | Zig 0.13 binary > 200KB |
| **Memory Check** | Zig testing allocator leak detection + Valgrind | N/A (reporting only) |

## Binary Size Targets

| Target | Limit | Notes |
|--------|-------|-------|
| Zig 0.13 ReleaseSmall (aarch64-linux-musl) | **200 KB** | Hard CI gate. Our claim is ~180KB. |
| Zig 0.15 ReleaseSmall | No gate | Tracked for comparison |

## Test Structure

Tests live alongside source code in `src/`:

- **`src/tools.zig`** — Tool dispatch tests (bash, read/write/edit file, search, list_files, glob matching)
- **`src/arena.zig`** — Fixed arena allocator tests (basic alloc, overflow, alignment, peak tracking, presets)
- **`src/json.zig`** — JSON parser tests (field extraction, request building)
- **`src/stream.zig`** — SSE stream parser tests

## Adding New Tests

1. Add `test "descriptive name" { ... }` blocks in the relevant `src/*.zig` file
2. Use `std.testing.allocator` for tests that should be leak-checked
3. Use `std.heap.page_allocator` for tests where the SUT allocates memory it doesn't free (e.g., tool execute tests)
4. Guard profile-specific tests: `if (build_options.profile != .coding) return;`
5. Run `zig build test` locally before pushing

## QEMU Testing (Local)

For local cross-architecture testing on macOS/Linux:

```bash
# Install QEMU (macOS)
brew install qemu

# Build cross-compiled binary
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-linux-musl

# Run via QEMU (Linux only — QEMU user-mode doesn't work on macOS)
qemu-aarch64-static zig-out/bin/yoctoclaw --version

# On macOS, use the CI instead — it runs on Ubuntu where QEMU user-mode works
```

## Known Issues

- **macOS /tmp resolution**: `/tmp` symlinks to `/private/tmp` on macOS. The path allowlist handles both.
- **Tool test allocations**: Tool `execute()` returns allocated strings without a free path (by design — production uses arena reset). Tests use `page_allocator` to avoid false leak reports.

## Debugging Test Failures

```bash
# Verbose test output
zig build test 2>&1 | less

# Build only (check compilation)
zig build -Doptimize=Debug

# Single architecture cross-compile check
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSmall
```
